#!/usr/bin/env bash
# Verify Weep can fetch credentials for every EMR-monitor role (forno + prod).
# Environment selection happens in the Streamlit UI only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_WEEP_CANDIDATES=(
	"${WEEP_BIN:-}"
	"${SCRIPT_DIR}/../../packages/emr-cli/dist/weep"
	"$(command -v weep 2>/dev/null || true)"
)
WEEP_BIN=""
for candidate in "${_WEEP_CANDIDATES[@]}"; do
	if [[ -n "${candidate}" && -x "${candidate}" ]]; then
		WEEP_BIN="${candidate}"
		break
	fi
done

if [[ -z "${WEEP_BIN}" ]]; then
	echo "Error: weep not found. Set WEEP_BIN or install via bi-etl-ejuice packages/emr-cli (make -C ../../packages/emr-cli weep-install)." >&2
	exit 1
fi

export WEEP_BIN

if [[ ! -e ~/.weep/weep.yaml ]]; then
	mkdir -p ~/.weep
	read -rp "QuintoAndar email for Weep/ConsoleMe: " QA_EMAIL
	cat >~/.weep/weep.yaml <<EOF
authentication_method: challenge
challenge_settings:
  user: "${QA_EMAIL}"
consoleme_url: https://consoleme.sre.quintoandar.com.br
mtls_settings:
  old_cert_message: mTLS certificate is too old, please refresh mtls certificate
server:
  http_timeout: 20
  port: 9091
EOF
fi

_test_role() {
	local label="$1"
	local role_arn="$2"
	echo "==> ${label}"
	echo "    Role: ${role_arn}"
	if ! creds="$("${WEEP_BIN}" credential_process "${role_arn}")"; then
		echo "Error: Weep could not fetch credentials for ${label}." >&2
		exit 1
	fi
	uv run python -c "import json,sys; data=json.load(sys.stdin); print(f\"    Access key: {data['AccessKeyId'][:8]}…\"); exp=data.get('Expiration'); print(f\"    Expires:    {exp}\") if exp else None" <<<"${creds}"
}

echo "Authenticating all roles (forno + prod)…"
echo ""

cd "${SCRIPT_DIR}"
while IFS=$'\t' read -r env_name role_kind role_arn; do
	_test_role "${env_name} ${role_kind}" "${role_arn}"
	echo ""
done < <(uv run python -c "
from aws import ENVIRONMENTS, available_environments

for env in available_environments():
    roles = ENVIRONMENTS[env]
    print(f'{env}\tEMR\t{roles[\"emr\"]}')
    print(f'{env}\tEC2\t{roles[\"ec2\"]}')
")

echo "Auth OK for all environments. Starting the UI..."
uv sync && uv run streamlit run app.py
