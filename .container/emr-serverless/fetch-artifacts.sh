#!/bin/sh
# Download private wheels and JARs into ci-staged/ before the Docker build.
#
# CI: Woodpecker runs this with the pipeline IAM role (no repo secrets).
# Local: `make build-emr-serverless-notebook` calls this first; needs AWS creds
# in the environment (same as a manual `aws s3 cp`).
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)
ARTIFACTS_BUCKET=${ARTIFACTS_BUCKET:-s3://artifacts.s3.data.quintoandar.com.br}
WHEELS_DIR="${SCRIPT_DIR}/ci-staged/wheels"
JARS_DIR="${SCRIPT_DIR}/ci-staged/jars"
WHEELS_LIST="${SCRIPT_DIR}/internal-wheels.txt"
JARS_LIST="${SCRIPT_DIR}/jars.txt"

cd "${REPO_ROOT}"

command -v aws >/dev/null 2>&1 || {
  echo "aws CLI not found — install AWS CLI v2 or use the official aws-cli image in CI" >&2
  exit 1
}

rm -rf "${WHEELS_DIR}" "${JARS_DIR}"
mkdir -p "${WHEELS_DIR}" "${JARS_DIR}"

fetch_list() {
  list_file=$1
  dest_dir=$2
  label=$3

  while read -r key; do
    case "${key}" in ''|\#*) continue ;; esac
    echo "  fetching ${label}: ${key}"
    aws s3 cp "${ARTIFACTS_BUCKET}/${key}" "${dest_dir}/$(basename "${key}")"
  done < "${list_file}"
}

echo "Fetching EMR Serverless build artifacts from ${ARTIFACTS_BUCKET}"
fetch_list "${WHEELS_LIST}" "${WHEELS_DIR}" wheel
while read -r key; do
  case "${key}" in ''|\#*) continue ;; esac
  echo "  fetching jar: ${key}"
  aws s3 cp "${ARTIFACTS_BUCKET}/${key}" "${JARS_DIR}/$(basename "${key}")" \
    || echo "  WARN: ${key} not found in S3, skipping"
done < "${JARS_LIST}"

echo "Staged wheels:"
ls -la "${WHEELS_DIR}"
echo "Staged jars:"
ls -la "${JARS_DIR}"

test "$(find "${WHEELS_DIR}" -name '*.whl' | wc -l | tr -d ' ')" -gt 0 \
  || { echo "No wheels staged — check AWS credentials and ${ARTIFACTS_BUCKET}" >&2; exit 1; }
