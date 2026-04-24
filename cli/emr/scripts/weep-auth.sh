#!/usr/bin/env bash
set -euo pipefail

# TODO: switch to sso_DataAndAnalyticsEMRUser_staff profile
_WEEP_ROLE_FORNO_DEFAULT="${WEEP_ROLE_ARN_FORNO:-arn:aws:iam::713278628093:role/sso_DataAndAnalyticsEMRAdmin_staff}"
_WEEP_ROLE_PROD_DEFAULT="${WEEP_ROLE_ARN_PROD:-arn:aws:iam::206390561754:role/sso_DataAndAnalyticsEMRAdmin_staff}"

_emr_env_raw="${EMR_ENVIRONMENT:-prod}"
_emr_env="$(printf '%s' "${_emr_env_raw}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
[ -z "${_emr_env}" ] && _emr_env=prod

case "${_emr_env}" in
	prod) WEEP_ROLE="${_WEEP_ROLE_PROD_DEFAULT}" ;;
	forno) WEEP_ROLE="${_WEEP_ROLE_FORNO_DEFAULT}" ;;
	*)
		echo "Error: EMR_ENVIRONMENT must be prod or forno (empty defaults to prod); got '${_emr_env_raw}'" >&2
		exit 1
		;;
esac

# Creating Weep config file
if ! [ -e ~/.weep/weep.yaml ]; then
	read -rp "Please enter your QuintoAndar email: " QA_EMAIL

	echo \
		"
authentication_method: challenge
challenge_settings:
  user: ${QA_EMAIL}
consoleme_url: https://consoleme.sre.quintoandar.com.br
mtls_settings:
  old_cert_message: mTLS certificate is too old, please refresh mtls certificate
server:
  http_timeout: 20
  port: 9091
" >~/.weep/weep.yaml
fi

# Creating config file with default region
if ! [ -e ~/.aws/config ]; then
	mkdir -p ~/.aws
	touch ~/.aws/config
	echo -e "[default]\nregion = us-east-1" >~/.aws/config
fi

# Use Weep CLI to authenticate (ConsoleMe role for this environment)
weep file -f "${WEEP_ROLE}"
weep whoami