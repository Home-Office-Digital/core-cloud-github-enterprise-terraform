#!/usr/bin/env bash
# GHES Certificate Renewal Script
# Location on instance: /opt/cert-renewal.sh
#
# logic and how it should work:
#   15 days to expiry : Slack warning, renewal will run tomorrow
#   14 days to expiry : Issue cert via acme.sh
#   All other days    : Silent exit, log entry only

set -euo pipefail

# Hostname and Slack webhook injected via terragrunt repo variables
GHES_HOSTNAME="${ghes_hostname}"
SLACK_WEBHOOK_URL="${slack_webhook_url}"

# acme.sh runs as root
ACME_CERT_DIR="/root/.acme.sh/$${GHES_HOSTNAME}"
TMP_COMBINED="/tmp/combined.pem"

# AWS Secrets Manager secret names for ZeroSSL EAB credentials (these are in opstooling accounts for each env)
SECRETS_MANAGER_EAB_KID_SECRET="eab-kid"
SECRETS_MANAGER_EAB_HMAC_SECRET="eab-hmac-key"

# ZeroSSL ACME server
ACME_SERVER="https://acme.zerossl.com/v2/DV90"

# Log file
LOG_FILE="/var/log/ghes-cert-renewal.log"

# Days before expiry to warn and renew
WARN_DAYS=15
RENEW_DAYS=14

# How long to wait for ghe-ssl-certificate-setup
# Retries every 30 seconds
APPLY_WAIT_RETRIES=10
APPLY_WAIT_INTERVAL=30

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE" >&2
}

slack_notify() {
  local title="$1"
  local message="$2"

  local payload
  payload=$(printf '{"title": "%s", "message": "%s"}' "$title" "$message")

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    -H 'Content-type: application/json' \
    --data "$payload" \
    "$SLACK_WEBHOOK_URL")

  if [[ "$http_code" != "200" ]]; then
    log "WARNING: Slack notify returned HTTP $${http_code}. Message may not have delivered."
  fi
}

# Read days until expiry directly from ghe-motd command
get_days_until_expiry() {
  local motd_days
  motd_days=$(ghe-motd 2>/dev/null | grep -i "Certificate will expire in" | grep -oP '\d+(?= days)' || true)

  if [[ -z "$motd_days" ]]; then
    log "ERROR: Could not read certificate expiry from ghe-motd."
    echo "-1"
    return
  fi

  echo "$motd_days"
}

wait_and_get_expiry() {
  log "Waiting for certificate propagation before reading new expiry."

  local attempt=1
  local motd_days

  while [[ "$attempt" -le "$APPLY_WAIT_RETRIES" ]]; do
    log "Checking ghe-motd for updated expiry. Attempt $${attempt} of $${APPLY_WAIT_RETRIES}."

    motd_days=$(ghe-motd 2>/dev/null | grep -i "Certificate will expire in" | grep -oP '\d+(?= days)' || true)

    if [[ -n "$motd_days" && "$motd_days" -gt "$RENEW_DAYS" ]]; then
      log "ghe-motd confirms certificate updated. Expires in $${motd_days} days."
      echo "$${motd_days} days"
      return
    fi

    log "Certificate not yet updated in ghe-motd. Waiting $${APPLY_WAIT_INTERVAL} seconds."
    sleep "$APPLY_WAIT_INTERVAL"
    (( attempt++ ))
  done

  log "WARNING: ghe-motd did not confirm update after all retries."
  echo "unknown"
}

# Get EAB credentials from AWS Secrets Manager
fetch_eab_credentials() {
  log "Fetching EAB credentials from AWS Secrets Manager."

  local raw_kid raw_hmac

  raw_kid=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRETS_MANAGER_EAB_KID_SECRET" \
    --query SecretString \
    --output text 2>&1) || {
    log "ERROR: Failed to fetch EAB_KID from Secrets Manager: $${raw_kid}"
    slack_notify "GHES Cert Renewal Failed. $${GHES_HOSTNAME}" \
      "Could not retrieve EAB_KID from Secrets Manager. Check IAM permissions on this instance. Certificate expires in $${days} days. Manual intervention required."
    exit 1
  }

  raw_hmac=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRETS_MANAGER_EAB_HMAC_SECRET" \
    --query SecretString \
    --output text 2>&1) || {
    log "ERROR: Failed to fetch EAB_HMAC from Secrets Manager: $${raw_hmac}"
    slack_notify "GHES Cert Renewal Failed. $${GHES_HOSTNAME}" \
      "Could not retrieve EAB_HMAC from Secrets Manager. Check IAM permissions on this instance. Certificate expires in $${days} days. Manual intervention required."
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
register_acme_account() {
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
      "ZeroSSL account registration failed. This usually means the EAB credentials are invalid or expired. Check the values in Secrets Manager. Certificate expires in $${days} days. Manual intervention required."
    exit 1
  fi

  log "acme.sh account registration succeeded."
}

# Issue certs
issue_certificate() {
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
      "Certificate issuance failed for $${GHES_HOSTNAME}. Common causes: Route53 IAM permissions, DNS propagation timeout, ZeroSSL rate limit. Certificate expires in $${days} days. Manual intervention required."
    exit 1
  fi

  # Combine into single PEM
  cat "$${ACME_CERT_DIR}/$${GHES_HOSTNAME}.key" "$${ACME_CERT_DIR}/fullchain.cer" > "$TMP_COMBINED"
  log "Certificate issued successfully. Combined PEM written to $${TMP_COMBINED}."
}

# Apply the cert to GHES
apply_certificate() {
  log "Applying certificate via ghe-ssl-certificate-setup."

  cd /usr/local/share/enterprise

  local output exit_code
  output=$(./ghe-ssl-certificate-setup -c "$TMP_COMBINED" 2>&1) && exit_code=0 || exit_code=$?

  echo "$output" >> "$LOG_FILE"

  if [[ "$exit_code" -ne 0 ]]; then
    log "ERROR: ghe-ssl-certificate-setup failed (exit $${exit_code})"
    slack_notify "GHES Cert Apply Failed. $${GHES_HOSTNAME}" \
      "Certificate was issued successfully but ghe-ssl-certificate-setup failed. The combined PEM is at $${TMP_COMBINED} on the instance if you need to apply manually. Certificate expires in $${days} days."
    exit 1
  fi

  log "ghe-ssl-certificate-setup completed. Waiting for propagation."
}

# Clean up
cleanup() {
  rm -f "$TMP_COMBINED"
  log "Temporary cert files removed."
}

main() {
  log "Starting cert check for $${GHES_HOSTNAME}"

  local days
  days=$(get_days_until_expiry)
  log "Days until expiry: $${days}"

  if [[ "$days" -eq -1 ]]; then
    slack_notify "GHES Cert Check Failed. $${GHES_HOSTNAME}" \
      "Could not read certificate expiry from ghe-motd. Manual investigation required."
    exit 1
  fi

  if [[ "$days" -eq "$WARN_DAYS" ]]; then
    log "Certificate expires in $${days} days. Sending advance warning."
    slack_notify "GHES Certificate Expiry Warning. $${GHES_HOSTNAME}" \
      "The TLS certificate for $${GHES_HOSTNAME} expires in $${days} days. Automatic renewal will be attempted tomorrow at the scheduled cron time. No action required unless you want to renew earlier."

  elif [[ "$days" -eq "$RENEW_DAYS" ]]; then
    log "Certificate expires in $${days} days. Starting renewal process."

    fetch_eab_credentials
    register_acme_account
    issue_certificate
    apply_certificate
    cleanup

    local new_expiry
    new_expiry=$(wait_and_get_expiry)
    log "Renewal complete. Certificate now expires in $${new_expiry}."

    slack_notify "GHES Certificate Renewed. $${GHES_HOSTNAME}" \
      "The TLS certificate for $${GHES_HOSTNAME} has been successfully renewed. Certificate now expires in $${new_expiry}. Propagation can take up to 5 minutes."

  else
    log "Certificate expires in $${days} days. No action required."
  fi
}

main "$@"
