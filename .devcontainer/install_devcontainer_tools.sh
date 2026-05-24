#!/usr/bin/env bash
# Installs devcontainer CLIs (astro, yq, aws, databricks, starship, weep,
# woodpecker-cli, QLI).
#
# First argument is the Docker / OCI platform CPU segment (same names as Dockerfile
# ARG TARGETARCH and `dpkg --print-architecture` on Debian): amd64 or arm64.
# It is NOT necessarily the same as `uname -m` (e.g. aarch64 on arm64 hardware).
#
# Upstream download naming differs by vendor; this script maps:
#   - Most GitHub tarballs/zip: linux_${TARGETARCH} (amd64 | arm64)
#   - AWS CLI v2 installer zip: linux-${AWS_ARCH} (x86_64 | aarch64)
#   - Starship musl tarball: ${AWS_ARCH}-unknown-linux-musl (x86_64 | aarch64)
#   - Weep tarball: linux_${WEEP_ARCH} (x86_64 | arm64 — Netflix uses arm64, not aarch64)
#
# Usage: install_devcontainer_tools.sh <cpu> ASTRO_CLI_VERSION YQ_VERSION \
#   AWSCLI_VERSION DATABRICKS_CLI_VERSION STARSHIP_VERSION WEEP_VERSION WOODPECKER_CLI_VERSION
set -euo pipefail

if [[ "$#" -ne 8 ]]; then
  echo "usage: $0 <cpu> ASTRO_CLI_VERSION YQ_VERSION AWSCLI_VERSION DATABRICKS_CLI_VERSION STARSHIP_VERSION WEEP_VERSION WOODPECKER_CLI_VERSION" >&2
  echo "  <cpu>: amd64|arm64 (also accepts x86_64 -> amd64, aarch64 -> arm64)" >&2
  exit 1
fi

_raw_cpu="${1}"
case "${_raw_cpu}" in
  amd64 | x86_64) TARGETARCH=amd64 ;;
  arm64 | aarch64) TARGETARCH=arm64 ;;
  *)
    echo "unsupported cpu (expected amd64|arm64, got: ${_raw_cpu})" >&2
    exit 1
    ;;
esac
ASTRO_CLI_VERSION="$2"
YQ_VERSION="$3"
AWSCLI_VERSION="$4"
DATABRICKS_CLI_VERSION="$5"
STARSHIP_VERSION="$6"
WEEP_VERSION="$7"
WOODPECKER_CLI_VERSION="$8"

if [[ "${TARGETARCH}" == amd64 ]]; then
  AWS_ARCH=x86_64
  WEEP_ARCH=x86_64
elif [[ "${TARGETARCH}" == arm64 ]]; then
  AWS_ARCH=aarch64
  WEEP_ARCH=arm64
else
  echo "internal error: unexpected TARGETARCH=${TARGETARCH}" >&2
  exit 1
fi

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
