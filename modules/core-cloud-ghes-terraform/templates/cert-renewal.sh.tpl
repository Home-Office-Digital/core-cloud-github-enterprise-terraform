#!/usr/bin/env bash
# GHES Certificate Renewal Script
# Location on instance: /opt/cert-renewal.sh
#
# Run daily from cron. Warn at 15 days and renew at 14 days or less.

set -euo pipefail

# Hostname and Slack webhook injected via Terraform at build time
GHES_HOSTNAME="${ghes_hostname}"
SLACK_WEBHOOK_URL="${slack_webhook_url}"

# Script defaults
NOTIFY_SLACK="true"
RENEW_NOW="false"

# acme.sh uses ECC certificates by default, stored in the _ecc directory.
ACME_CERT_DIR="/root/.acme.sh/$${GHES_HOSTNAME}_ecc"
TMP_COMBINED="/tmp/combined.pem"

# AWS Secrets Manager secret names for ZeroSSL EAB credentials
SECRETS_MANAGER_EAB_KID_SECRET="eab-kid"
SECRETS_MANAGER_EAB_HMAC_SECRET="eab-hmac-key"

# ZeroSSL ACME server
ACME_SERVER="https://acme.zerossl.com/v2/DV90"

# Log file
LOG_FILE="/var/log/ghes-cert-renewal.log"

# Days before expiry to warn and renew
WARN_DAYS=15
RENEW_DAYS=14

# How long to wait for ghe-config-apply to propagate before reading the new expiry.
APPLY_WAIT_RETRIES=10
APPLY_WAIT_INTERVAL=30

usage() {
  cat <<'EOF'
Usage: /opt/cert-renewal.sh [OPTION]

Check the GHES certificate and renew it through ZeroSSL when it has 14 days
or fewer remaining. The script is normally run daily by cron as root.

Options:
  -h, --help, -help       Show this help and exit.
  --force, --force-renewal
                          Renew without checking the remaining certificate age.

Force renewal example:
  sudo /opt/cert-renewal.sh --force

Prerequisites: root access, acme.sh with Route53 DNS support, AWS CLI access
to the EAB secrets, curl, ghe-config, and ghe-config-apply.
EOF
}

FORCE_RENEWAL=false

parse_args() {
  case "$#" in
    0) ;;
    1)
      case "$1" in
        -h|--help|-help)
          usage
          exit 0
          ;;
        --force|--force-renewal|--now)
          FORCE_RENEWAL=true
          RENEW_NOW="true"
          ;;
        *)
          echo "ERROR: Unknown option: $1" >&2
          usage >&2
          exit 2
          ;;
      esac
      ;;
    *)
      echo "ERROR: Only one option may be supplied." >&2
      usage >&2
      exit 2
      ;;
  esac
}

parse_args "$@"

# Prevent multiple instances running simultaneously
LOCKFILE="/tmp/cert-renewal.lock"
if ! mkdir "$LOCKFILE" 2>/dev/null; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Another instance is running. Exiting." >> "$LOG_FILE"
  exit 0
fi

TMP_COMBINED=""
cleanup() {
  if [[ -n "$TMP_COMBINED" ]]; then
    rm -f "$TMP_COMBINED"
    TMP_COMBINED=""
  fi
}

cleanup_on_exit() {
  cleanup
  rm -rf "$LOCKFILE"
}

trap cleanup_on_exit EXIT

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE" >&2
}

slack_notify() {
  local title="$1"
  local message="$2"

  if [[ "$${NOTIFY_SLACK,,}" != "true" ]]; then
    log "Slack notifications disabled. Skipping notification: $${title}"
    return 0
  fi

  if [[ -z "$SLACK_WEBHOOK_URL" ]]; then
    log "WARNING: Slack notifications enabled but SLACK_WEBHOOK_URL is empty. Skipping notification: $${title}"
    return 0
  fi

  local payload
  payload=$(printf '{"title": "%s", "message": "%s"}' "$title" "$message")

  local http_code
  http_code=$(curl -s -o /dev/null -w "%%{http_code}" \
    -X POST \
    -H 'Content-type: application/json' \
    --data "$payload" \
    "$SLACK_WEBHOOK_URL" || true)

  if [[ "$http_code" != "200" ]]; then
    log "WARNING: Slack notify returned HTTP $${http_code}. Message may not have delivered."
  fi
}

# Read days until expiry from ghe-motd. Keep all parsing in one place because
# the command is also used to confirm propagation after applying a certificate.
get_days_until_expiry() {
  local motd_days
  motd_days=$(ghe-motd 2>/dev/null | awk '
    tolower($0) ~ /certificate will expire in/ {
      for (i = 1; i <= NF; i++) {
        if (tolower($i) == "days" && $(i - 1) ~ /^[0-9]+$/) {
          print $(i - 1)
          exit
        }
      }
    }
  ' || true)

  if [[ -z "$motd_days" ]]; then
    log "ERROR: Could not read certificate expiry from ghe-motd."
    return 1
  fi

  echo "$motd_days"
}

# After apply, poll ghe-motd until it reports the new expiry
# Retries every 30 seconds up to APPLY_WAIT_RETRIES attempts
wait_and_get_expiry() {
  log "Waiting for certificate propagation before reading new expiry."

  local attempt=1
  local motd_days

  while [[ "$attempt" -le "$APPLY_WAIT_RETRIES" ]]; do
    log "Checking ghe-motd for updated expiry. Attempt $${attempt} of $${APPLY_WAIT_RETRIES}."

    motd_days=$(get_days_until_expiry || true)

    if [[ -n "$motd_days" && "$motd_days" -gt "$RENEW_DAYS" ]]; then
      log "ghe-motd confirms certificate updated. Expires in $${motd_days} days."
      echo "$${motd_days} days"
      return
    fi

    log "Certificate not yet updated in ghe-motd. Waiting $${APPLY_WAIT_INTERVAL} seconds."
    sleep "$APPLY_WAIT_INTERVAL"
    (( attempt++ ))
  done

  log "ERROR: ghe-motd did not confirm certificate propagation after all retries."
  return 1
}

# Fetch EAB credentials from AWS Secrets Manager at runtime
# Secrets are stored as JSON objects e.g. {"eab-kid": "value"} and {"eab-hmac-key": "value"}
fetch_eab_credentials() {
  local expiry_context="$1"

  log "Fetching EAB credentials from AWS Secrets Manager."

  local raw_kid raw_hmac

  raw_kid=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRETS_MANAGER_EAB_KID_SECRET" \
    --query SecretString \
    --output text 2>&1) || {
    log "ERROR: Failed to fetch EAB_KID from Secrets Manager: $${raw_kid}"
    slack_notify "GHES Cert Renewal Failed. $${GHES_HOSTNAME}" \
      "Could not retrieve EAB_KID from Secrets Manager. Check IAM permissions on this instance. Certificate expiry context: $${expiry_context}. Manual intervention required."
    exit 1
  }

  raw_hmac=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRETS_MANAGER_EAB_HMAC_SECRET" \
    --query SecretString \
    --output text 2>&1) || {
    log "ERROR: Failed to fetch EAB_HMAC from Secrets Manager: $${raw_hmac}"
    slack_notify "GHES Cert Renewal Failed. $${GHES_HOSTNAME}" \
      "Could not retrieve EAB_HMAC from Secrets Manager. Check IAM permissions on this instance. Certificate expiry context: $${expiry_context}. Manual intervention required."
    exit 1
  }

  EAB_KID=$(echo "$raw_kid" | python3 -c "import sys, json; print(json.load(sys.stdin)['$${SECRETS_MANAGER_EAB_KID_SECRET}'])") || {
    log "ERROR: Failed to parse EAB_KID from secret JSON"
    slack_notify "GHES Cert Renewal Failed. $${GHES_HOSTNAME}" \
      "Retrieved EAB_KID secret but could not parse the value. Check the secret format in Secrets Manager."
    exit 1
  }

  EAB_HMAC=$(echo "$raw_hmac" | python3 -c "import sys, json; print(json.load(sys.stdin)['$${SECRETS_MANAGER_EAB_HMAC_SECRET}'])") || {
    log "ERROR: Failed to parse EAB_HMAC from secret JSON"
    slack_notify "GHES Cert Renewal Failed. $${GHES_HOSTNAME}" \
      "Retrieved EAB_HMAC secret but could not parse the value. Check the secret format in Secrets Manager."
    exit 1
  }

  log "EAB credentials fetched and parsed successfully."
}

# Register acme.sh account with ZeroSSL using EAB credentials
# Idempotent. acme.sh skips re-registration if the account already exists
register_acme_account() {
  local expiry_context="$1"

  log "Registering acme.sh account with ZeroSSL."

  local output exit_code
  output=$(acme.sh --register-account \
    --server "$ACME_SERVER" \
    --eab-kid "$EAB_KID" \
    --eab-hmac-key "$EAB_HMAC" 2>&1) && exit_code=0 || exit_code=$?

  echo "$output" >> "$LOG_FILE"

  if [[ "$exit_code" -ne 0 ]]; then
    log "ERROR: acme.sh account registration failed (exit $${exit_code})"
    slack_notify "GHES Cert Renewal Failed. $${GHES_HOSTNAME}" \
      "ZeroSSL account registration failed. This usually means the EAB credentials are invalid or expired. Check the values in Secrets Manager. Certificate expiry context: $${expiry_context}. Manual intervention required."
    exit 1
  fi

  log "acme.sh account registration succeeded."
}

# Issue wildcard certificate via ZeroSSL + Route53 DNS validation
# acme.sh stores certs under /root/.acme.sh automatically, key and fullchain combined after issuance
issue_certificate() {
  local expiry_context="$1"

  log "Issuing wildcard certificate for $${GHES_HOSTNAME} via ZeroSSL and Route53."

  local output exit_code
  output=$(acme.sh --issue \
    --server "$ACME_SERVER" \
    --dns dns_aws \
    -d "$${GHES_HOSTNAME}" \
    -d "*.$${GHES_HOSTNAME}" \
    --force 2>&1) && exit_code=0 || exit_code=$?

  echo "$output" >> "$LOG_FILE"

  if [[ "$exit_code" -ne 0 ]]; then
    log "ERROR: Certificate issuance failed (exit $${exit_code})"
    slack_notify "GHES Cert Renewal Failed. $${GHES_HOSTNAME}" \
      "Certificate issuance failed for $${GHES_HOSTNAME}. Common causes: Route53 IAM permissions, DNS propagation timeout, ZeroSSL rate limit. Certificate expiry context: $${expiry_context}. Manual intervention required."
    exit 1
  fi

  # Combine key + fullchain into a temporary PEM for ghe-config.
  TMP_COMBINED=$(mktemp /tmp/ghes-cert-renewal.XXXXXX.pem)
  cat "$${ACME_CERT_DIR}/$${GHES_HOSTNAME}.key" "$${ACME_CERT_DIR}/fullchain.cer" > "$TMP_COMBINED"
  log "Certificate issued successfully. Combined PEM written to $${TMP_COMBINED}."
}

# Apply the certificate to GHES using ghe-config and ghe-config-apply
# ghe-ssl-certificate-setup requires a TTY and fails via cron
apply_certificate() {
  local expiry_context="$1"

  log "Applying certificate via ghe-config and ghe-config-apply."

  local output exit_code

  output=$(ghe-config 'github-ssl.cert' "$(cat "$TMP_COMBINED")" 2>&1) && exit_code=0 || exit_code=$?

  if [[ "$exit_code" -ne 0 ]]; then
    log "ERROR: ghe-config failed to store certificate (exit $${exit_code})"
    slack_notify "GHES Cert Apply Failed. $${GHES_HOSTNAME}" \
      "Certificate was issued but ghe-config failed to store it. The combined PEM is at $${TMP_COMBINED} if you need to apply manually. Certificate expiry context: $${expiry_context}."
    exit 1
  fi

  log "Certificate stored in ghe-config. Running ghe-config-apply."

  output=$(ghe-config-apply 2>&1) && exit_code=0 || exit_code=$?

  echo "$output" >> "$LOG_FILE"

  if [[ "$exit_code" -ne 0 ]]; then
    log "ERROR: ghe-config-apply failed (exit $${exit_code})"
    slack_notify "GHES Cert Apply Failed. $${GHES_HOSTNAME}" \
      "Certificate was stored but ghe-config-apply failed. Certificate expiry context: $${expiry_context}."
    exit 1
  fi

  log "ghe-config-apply completed. Waiting for propagation."
}

renew_certificate() {
  local expiry_context="$1"

  fetch_eab_credentials "$expiry_context"
  register_acme_account "$expiry_context"
  issue_certificate "$expiry_context"
  apply_certificate "$expiry_context"
  cleanup

  local new_expiry
  if ! new_expiry=$(wait_and_get_expiry); then
    log "ERROR: Certificate renewal was applied but propagation could not be confirmed."
    slack_notify "GHES Certificate Renewal Unconfirmed. $${GHES_HOSTNAME}" \
      "The certificate was issued and applied, but ghe-motd did not confirm propagation. Manual verification is required. Certificate expiry context: $${expiry_context}."
    return 1
  fi

  log "Renewal complete. Certificate now expires in $${new_expiry}."
  slack_notify "GHES Certificate Renewed. $${GHES_HOSTNAME}" \
    "The TLS certificate for $${GHES_HOSTNAME} has been successfully renewed. Certificate now expires in $${new_expiry}. Propagation can take up to 5 minutes."
}

main() {
  log "Starting certificate check for $${GHES_HOSTNAME}"

  local days
  if [[ "$FORCE_RENEWAL" == true || "$${RENEW_NOW,,}" == "true" ]]; then
    days="forced"
    log "Force renewal requested. Skipping certificate expiry check."
  elif ! days=$(get_days_until_expiry); then
    slack_notify "GHES Cert Check Failed. $${GHES_HOSTNAME}" \
      "Could not read certificate expiry from ghe-motd. Manual investigation required."
    exit 1
  else
    log "Days until expiry: $${days}"
  fi

  if [[ "$FORCE_RENEWAL" != true && "$${RENEW_NOW,,}" != "true" && "$days" -eq "$WARN_DAYS" ]]; then
    log "Certificate expires in $${days} days. Sending advance warning."
    slack_notify "GHES Certificate Expiry Warning. $${GHES_HOSTNAME}" \
      "The TLS certificate for $${GHES_HOSTNAME} expires in $${days} days. Automatic renewal will be attempted tomorrow at the scheduled cron time. No action required unless you want to renew earlier."

  elif [[ "$FORCE_RENEWAL" == true || "$${RENEW_NOW,,}" == "true" || "$days" -le "$RENEW_DAYS" ]]; then
    if [[ "$FORCE_RENEWAL" == true ]]; then
      log "Starting forced renewal process."
    else
      log "Certificate expires in $${days} days. Starting renewal process."
    fi

    renew_certificate "$days"

  else
    log "Certificate expires in $${days} days. No action required."
  fi
}

main "$@"