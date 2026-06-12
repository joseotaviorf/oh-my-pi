#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET_DIR="${PACKAGE_ROOT}/dist"
WEEP_BIN="${TARGET_DIR}/weep"

# Check if weep is already installed in dist
if [ -x "${WEEP_BIN}" ]; then
	echo "Weep is already installed. Skipping installation."
	exit 0
fi

# Determine OS and architecture
OS=$(uname | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

# Map architecture to Weep's naming convention
case "$ARCH" in
x86_64) ARCH="amd64" ;;
aarch64 | arm64) ARCH="arm64" ;;
*)
	echo "Unsupported architecture: $ARCH"
	exit 1
	;;
esac

# Set version
WEEP_VERSION="0.3.31"

mkdir -p "${TARGET_DIR}"

WEEP_EXTRACT_DIR=$(mktemp -d -t weep-install.XXXXXX)
trap 'rm -rf "${WEEP_EXTRACT_DIR}"' EXIT

# Download and extract the binary
TARBALL="weep_${WEEP_VERSION}_${OS}_${ARCH}.tar.gz"
URL="https://github.com/Netflix/weep/releases/download/v${WEEP_VERSION}/${TARBALL}"

curl -sL "$URL" | tar xzf - -C "${WEEP_EXTRACT_DIR}"

# Move binary to target dir
mv "${WEEP_EXTRACT_DIR}/bin/${OS}_${ARCH}/weep" "${WEEP_BIN}"
chmod +x "${WEEP_BIN}"

echo "Weep installed successfully at ${WEEP_BIN}"
