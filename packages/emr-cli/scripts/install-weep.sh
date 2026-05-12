#!/bin/bash
set -e

# Check if weep is already installed
if command -v weep >/dev/null 2>&1; then
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

# Set version and target directory
WEEP_VERSION="0.3.31"
TARGET_DIR="/usr/local/bin"

# Create directories
mkdir -p ~/.weep
mkdir -p ~/weep

# Download and extract the binary
TARBALL="weep_${WEEP_VERSION}_${OS}_${ARCH}.tar.gz"
URL="https://github.com/Netflix/weep/releases/download/v${WEEP_VERSION}/${TARBALL}"

curl -sL "$URL" | tar xzvf - -C ~/weep

# Move binary to target dir
mv ~/weep/bin/"${OS}_${ARCH}"/weep "$TARGET_DIR"

echo "Weep installed successfully at $TARGET_DIR/weep"
