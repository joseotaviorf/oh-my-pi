#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

# Same default as packages/emr-cli/scripts/weep-auth.sh (EMR RunJobFlow requires this role).
WEEP_FORNO_DATA_ROLE="${WEEP_FORNO_DATA_ROLE:-arn:aws:iam::713278628093:role/sso_DataAndAnalyticsEMRUser_staff}"

if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  if command -v weep >/dev/null 2>&1; then
    echo "AWS credentials not in environment; exporting via Weep (${WEEP_FORNO_DATA_ROLE})"
    # shellcheck disable=SC1090
    eval "$(weep export "${WEEP_FORNO_DATA_ROLE}")"
  fi
fi

if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  echo "Warning: AWS credentials not available; skipping aws_default connection (optional for non-EMR work)."
  echo "To configure EMR tasks later:"
  echo "  eval \$(weep export ${WEEP_FORNO_DATA_ROLE})"
  echo "  make import-local-aws-connection"
  exit 0
fi

REGION="${AWS_DEFAULT_REGION:-${AWS_REGION:-us-east-1}}"

echo "Configuring Airflow connection aws_default (region: ${REGION})"

EXTRA_JSON=$(jq -n \
  --arg region "$REGION" \
  --arg token "${AWS_SESSION_TOKEN:-}" \
  '{
    region_name: $region
  } + (if $token != "" then {aws_session_token: $token} else {} end)')

astro dev run connections delete aws_default 2>/dev/null || true

echo "  Using AWS_ACCESS_KEY_ID from environment"
astro dev run connections add aws_default \
  --conn-type aws \
  --conn-login "$AWS_ACCESS_KEY_ID" \
  --conn-password "$AWS_SECRET_ACCESS_KEY" \
  --conn-extra "$EXTRA_JSON" < /dev/null

echo "Airflow aws_default connection configured."
