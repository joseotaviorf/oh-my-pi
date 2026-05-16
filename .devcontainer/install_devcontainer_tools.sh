#!/usr/bin/env bash
# Installs devcontainer CLIs (astro, yq, aws, databricks, starship, weep,
# woodpecker-cli, QLI).
# Usage: install_devcontainer_tools.sh TARGETARCH ASTRO_CLI_VERSION YQ_VERSION \
#   AWSCLI_VERSION DATABRICKS_CLI_VERSION STARSHIP_VERSION WEEP_VERSION WOODPECKER_CLI_VERSION
set -euo pipefail

if [[ "$#" -ne 8 ]]; then
  echo "usage: $0 TARGETARCH ASTRO_CLI_VERSION YQ_VERSION AWSCLI_VERSION DATABRICKS_CLI_VERSION STARSHIP_VERSION WEEP_VERSION WOODPECKER_CLI_VERSION" >&2
  exit 1
fi

TARGETARCH="$1"
ASTRO_CLI_VERSION="$2"
YQ_VERSION="$3"
AWSCLI_VERSION="$4"
DATABRICKS_CLI_VERSION="$5"
STARSHIP_VERSION="$6"
WEEP_VERSION="$7"
WOODPECKER_CLI_VERSION="$8"

case "${TARGETARCH}" in
  amd64) AWS_ARCH=x86_64; WEEP_ARCH=x86_64 ;;
  arm64) AWS_ARCH=aarch64; WEEP_ARCH=arm64 ;;
  *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;;
esac

curl -fsSL "https://github.com/astronomer/astro-cli/releases/download/v${ASTRO_CLI_VERSION}/astro_${ASTRO_CLI_VERSION}_linux_${TARGETARCH}.tar.gz" \
  | tar -xz -C /usr/local/bin astro

curl -fsSL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${TARGETARCH}" \
  -o /usr/local/bin/yq
chmod +x /usr/local/bin/yq

curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}-${AWSCLI_VERSION}.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli
rm -rf /tmp/awscliv2.zip /tmp/aws

curl -fsSL "https://github.com/databricks/cli/releases/download/v${DATABRICKS_CLI_VERSION}/databricks_cli_${DATABRICKS_CLI_VERSION}_linux_${TARGETARCH}.zip" -o /tmp/dbcli.zip
unzip -q /tmp/dbcli.zip -d /tmp/dbcli
mv /tmp/dbcli/databricks /usr/local/bin/databricks
rm -rf /tmp/dbcli /tmp/dbcli.zip

curl -fsSL "https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-${AWS_ARCH}-unknown-linux-musl.tar.gz" \
  | tar -xz -C /usr/local/bin starship

WEEP_URL="https://github.com/Netflix/weep/releases/download/v${WEEP_VERSION}/weep_${WEEP_VERSION}_linux_${WEEP_ARCH}.tar.gz"
mkdir -p /tmp/weep-extract
curl -fsSL "${WEEP_URL}" | tar -xz -C /tmp/weep-extract
WEEP_BIN="$(find /tmp/weep-extract -type f -name weep -print -quit)"
test -n "${WEEP_BIN}"
install -m 0755 "${WEEP_BIN}" /usr/local/bin/weep
rm -rf /tmp/weep-extract

curl -fsSL "https://github.com/woodpecker-ci/woodpecker/releases/download/v${WOODPECKER_CLI_VERSION}/woodpecker-cli_linux_${TARGETARCH}.tar.gz" \
  | tar -xz -C /usr/local/bin woodpecker-cli

QLI_URL="https://qli-http.apps.core-prd.habitat.zone/install"
if curl -fL --connect-timeout 20 --max-time 120 "${QLI_URL}" -o /tmp/qli-install.sh; then
  sed -e 's/sudo //g' /tmp/qli-install.sh | bash
else
  echo "warning: QLI install skipped (needs Zscaler/VPN/office Wi-Fi; unreachable from this build network)" >&2
fi
rm -f /tmp/qli-install.sh
