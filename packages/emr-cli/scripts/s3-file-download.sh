#!/usr/bin/env bash
# Download a single object from S3 to a local path. Run on the host after refreshing weep-backed AWS credentials.
#
# Usage:
#   ./scripts/s3-file-download.sh <s3-uri> <local-file>
#
# <s3-uri> must be a full object URI (e.g. s3://my-bucket/prefix/file.py), not only a prefix.

set -euo pipefail

usage() {
  echo "Usage: $0 <s3-uri> <local-file>" >&2
  echo "  Example: $0 s3://my-bucket/emr/jobs/sample_pi.py ./sample_pi.py" >&2
  exit 1
}

if [[ $# -ne 2 ]]; then
  usage
fi

S3_URI="$1"
LOCAL_FILE="$2"

if [[ "$S3_URI" != s3://* ]]; then
  echo "Source must be an s3:// object URI (e.g. s3://bucket/key)" >&2
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI not found; install AWS CLI v2 and ensure your profile/session is valid." >&2
  exit 1
fi

LOCAL_DIR="$(dirname "$LOCAL_FILE")"
if [[ "$LOCAL_DIR" != . ]]; then
  mkdir -p "$LOCAL_DIR"
fi

aws s3 cp "$S3_URI" "$LOCAL_FILE"
echo "Downloaded $S3_URI -> $LOCAL_FILE"
