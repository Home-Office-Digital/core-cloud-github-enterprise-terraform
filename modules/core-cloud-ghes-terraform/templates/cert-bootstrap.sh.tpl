#!/usr/bin/env bash
# GHES Initial Certificate Bootstrap Script
# Location on instance: /opt/cert-bootstrap.sh
# Purpose: Issue and apply certificate on startup only when expected hostnames are missing.

set -euo pipefail

GHES_HOSTNAME="${ghes_hostname}"
GHES_ZONE_NAMES=(
%{ for zone_name in route53_zone_names ~}
"${zone_name}"
%{ endfor ~}
)
SLACK_WEBHOOK_URL="${slack_webhook_url}"

ACME_CERT_DIR="/root/.acme.sh/$${GHES_HOSTNAME}"
TMP_COMBINED="/tmp/combined.pem"

SECRETS_MANAGER_EAB_KID_SECRET="eab-kid"
SECRETS_MANAGER_EAB_HMAC_SECRET="eab-hmac-key"
ACME_SERVER="https://acme.zerossl.com/v2/DV90"
LOG_FILE="/var/log/ghes-cert-bootstrap.log"

LOCKFILE="/tmp/cert-bootstrap.lock"
if ! mkdir "$LOCKFILE" 2>/dev/null; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Another bootstrap instance is running. Exiting." >> "$LOG_FILE"
  exit 0
fi
trap 'rm -rf "$LOCKFILE"' EXIT

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE" >&2
}

slack_notify() {
  local title="$1"
  local message="$2"

  local payload
  payload=$(printf '{"title": "%s", "message": "%s"}' "$title" "$message")

  local http_code
  http_code=$(curl -s -o /dev/null -w "%%{http_code}" \
    -X POST \
    -H 'Content-type: application/json' \
    --data "$payload" \
    "$SLACK_WEBHOOK_URL")

  if [[ "$http_code" != "200" ]]; then
    log "WARNING: Slack notify returned HTTP $${http_code}."
  fi
}

fetch_eab_credentials() {
  log "Fetching EAB credentials from AWS Secrets Manager."

  local raw_kid raw_hmac

  raw_kid=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRETS_MANAGER_EAB_KID_SECRET" \
    --query SecretString \
    --output text 2>&1) || {
    log "ERROR: Failed to fetch EAB_KID: $${raw_kid}"
    slack_notify "GHES Cert Bootstrap Failed. $${GHES_HOSTNAME}" \
      "Could not retrieve EAB_KID from Secrets Manager."
    exit 1
  }

  raw_hmac=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRETS_MANAGER_EAB_HMAC_SECRET" \
    --query SecretString \
    --output text 2>&1) || {
    log "ERROR: Failed to fetch EAB_HMAC: $${raw_hmac}"
    slack_notify "GHES Cert Bootstrap Failed. $${GHES_HOSTNAME}" \
      "Could not retrieve EAB_HMAC from Secrets Manager."
    exit 1
  }

  EAB_KID=$(echo "$raw_kid" | python3 -c "import sys, json; print(json.load(sys.stdin)['$${SECRETS_MANAGER_EAB_KID_SECRET}'])") || {
    log "ERROR: Failed to parse EAB_KID."
    exit 1
  }

  EAB_HMAC=$(echo "$raw_hmac" | python3 -c "import sys, json; print(json.load(sys.stdin)['$${SECRETS_MANAGER_EAB_HMAC_SECRET}'])") || {
    log "ERROR: Failed to parse EAB_HMAC."
    exit 1
  }
}

register_acme_account() {
  log "Registering acme.sh account with ZeroSSL."

  local output exit_code
  output=$(acme.sh --register-account \
    --server "$ACME_SERVER" \
    --eab-kid "$EAB_KID" \
    --eab-hmac-key "$EAB_HMAC" 2>&1) && exit_code=0 || exit_code=$?

  echo "$output" >> "$LOG_FILE"

  if [[ "$exit_code" -ne 0 ]]; then
    log "ERROR: acme.sh account registration failed (exit $${exit_code})."
    exit 1
  fi
}

issue_certificate() {
  log "Issuing initial certificate for $${GHES_HOSTNAME} and SAN hostnames."

  local domain_args=( -d "$${GHES_HOSTNAME}" )
  for zone in "$${GHES_ZONE_NAMES[@]}"; do
    local candidate="github.$${zone}"
    if [[ "$${candidate}" != "$${GHES_HOSTNAME}" ]]; then
      domain_args+=( -d "$${candidate}" )
    fi
  done

  local output exit_code
  output=$(acme.sh --issue \
    --server "$ACME_SERVER" \
    --dns dns_aws \
    "$${domain_args[@]}" \
    --force 2>&1) && exit_code=0 || exit_code=$?

  echo "$output" >> "$LOG_FILE"

  if [[ "$exit_code" -ne 0 ]]; then
    log "ERROR: Initial certificate issuance failed (exit $${exit_code})."
    slack_notify "GHES Cert Bootstrap Failed. $${GHES_HOSTNAME}" \
      "Initial certificate issuance failed. Check Route53 IAM permissions and DNS propagation."
    exit 1
  fi

  cat "$${ACME_CERT_DIR}/$${GHES_HOSTNAME}.key" "$${ACME_CERT_DIR}/fullchain.cer" > "$TMP_COMBINED"
}

apply_certificate() {
  log "Applying initial certificate via ghe-config and ghe-config-apply."

  local output exit_code

  output=$(ghe-config 'github-ssl.cert' "$(cat "$TMP_COMBINED")" 2>&1) && exit_code=0 || exit_code=$?
  if [[ "$exit_code" -ne 0 ]]; then
    log "ERROR: ghe-config failed to store certificate (exit $${exit_code})."
    exit 1
  fi

  output=$(ghe-config-apply 2>&1) && exit_code=0 || exit_code=$?
  echo "$output" >> "$LOG_FILE"
  if [[ "$exit_code" -ne 0 ]]; then
    log "ERROR: ghe-config-apply failed (exit $${exit_code})."
    exit 1
  fi
}

cleanup() {
  rm -f "$TMP_COMBINED"
}

get_expected_domains() {
  local expected=("$${GHES_HOSTNAME}")

  for zone in "$${GHES_ZONE_NAMES[@]}"; do
    local candidate="github.$${zone}"
    if [[ "$${candidate}" != "$${GHES_HOSTNAME}" ]]; then
      expected+=("$${candidate}")
    fi
  done

  printf '%s\n' "$${expected[@]}" | sort -u
}

get_current_cert_domains() {
  local current_cert
  current_cert=$(ghe-config 'github-ssl.cert' 2>/dev/null || true)

  if [[ -z "$${current_cert}" ]]; then
    return 1
  fi

  printf '%s\n' "$${current_cert}" \
    | openssl x509 -noout -text 2>/dev/null \
    | grep -oE 'DNS:[^, ]+' \
    | sed 's/^DNS://' \
    | sort -u
}

cert_matches_expected_domains() {
  local expected_domains current_domains
  local expected_domain
  expected_domains=$(get_expected_domains)

  if ! current_domains=$(get_current_cert_domains); then
    log "No current GHES certificate found in config."
    return 1
  fi

  if [[ -z "$${current_domains}" ]]; then
    log "Current GHES certificate has no readable SAN DNS entries."
    return 1
  fi

  while IFS= read -r expected_domain; do
    if [[ -z "$${expected_domain}" ]]; then
      continue
    fi

    if ! grep -Fxq "$${expected_domain}" <<< "$${current_domains}"; then
      log "Current GHES certificate is missing expected hostname: $${expected_domain}"
      log "Expected (minimum): $${expected_domains//$'\n'/, }"
      log "Current SANs:        $${current_domains//$'\n'/, }"
      return 1
    fi
  done <<< "$${expected_domains}"

  log "Current GHES certificate already covers all expected hostnames."
  return 0
}

main() {
  log "Starting initial certificate bootstrap for $${GHES_HOSTNAME}."

  # Skip bootstrap if the currently configured certificate already covers the expected hostnames.
  if cert_matches_expected_domains; then
    log "Certificate already configured with expected hostnames. Skipping bootstrap."
    exit 0
  fi

  fetch_eab_credentials
  register_acme_account
  issue_certificate
  apply_certificate
  cleanup

  log "Initial certificate setup completed successfully."
  slack_notify "GHES Certificate Bootstrapped. $${GHES_HOSTNAME}" \
    "Initial TLS certificate has been issued and applied successfully."
}

main "$@"
