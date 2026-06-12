#!/usr/bin/env bash
# Upload a local file to S3. Run on the host after refreshing weep-backed AWS credentials.
#
# Usage:
#   ./scripts/s3-file-upload.sh <local-file> <s3-target-dir>
#
# <s3-target-dir> is an S3 prefix (e.g. s3://my-bucket/prefix/); the object key is the source basename.

set -euo pipefail

usage() {
  echo "Usage: $0 <local-file> <s3-target-dir>" >&2
  echo "  Example: $0 ./samples/job/sample_pi.py s3://my-bucket/emr/jobs/" >&2
  exit 1
}

if [[ $# -ne 2 ]]; then
  usage
fi

SOURCE="$1"
TARGET_DIR="$2"

if [[ ! -f "$SOURCE" ]]; then
  echo "Source file not found: $SOURCE" >&2
  exit 1
fi

if [[ "$TARGET_DIR" != s3://* ]]; then
  echo "Target dir must be an s3:// URI (e.g. s3://bucket/prefix/)" >&2
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI not found; install AWS CLI v2 and ensure your profile/session is valid." >&2
  exit 1
fi

DEST="${TARGET_DIR%/}/$(basename "$SOURCE")"
aws s3 cp "$SOURCE" "$DEST"
echo "Uploaded $SOURCE -> $DEST"
