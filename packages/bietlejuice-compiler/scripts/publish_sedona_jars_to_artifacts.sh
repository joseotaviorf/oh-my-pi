#!/usr/bin/env bash
#
# Publish Sedona JARs to the artifacts bucket (replaces DBFS FileStore/jars/sedona/...).
#
# Usage:
#   ./publish_sedona_jars_to_artifacts.sh <artifacts-bucket-uri> [sedona-version]
#
# Examples:
#   ./publish_sedona_jars_to_artifacts.sh s3://artifacts.s3.forno.data.quintoandar.com.br
#   ./publish_sedona_jars_to_artifacts.sh s3://artifacts.s3.data.quintoandar.com.br 1.2.1-incubating
#
# Optional: copy extra JARs from a local directory (e.g. one-time export from DBFS):
#   EXTRA_JARS_DIR=/path/to/jars ./publish_sedona_jars_to_artifacts.sh s3://...

set -euo pipefail

ARTIFACTS_BUCKET="${1:?Usage: $0 <s3://artifacts-bucket> [sedona-version]}"
SEDONA_VERSION="${2:-1.2.1-incubating}"
S3_PREFIX="${ARTIFACTS_BUCKET%/}/sedona/jars/${SEDONA_VERSION}/"
MAVEN_BASE="https://repo1.maven.org/maven2"

# Matches ebdb_location / custom_cluster_with_sedona (Spark 3.0 / Scala 2.12, 1.2.1-incubating).
MAVEN_JARS=(
    "org/apache/sedona/sedona-python-adapter-3.0_2.12/${SEDONA_VERSION}/sedona-python-adapter-3.0_2.12-${SEDONA_VERSION}.jar"
    "org/apache/sedona/sedona-viz-3.0_2.12/${SEDONA_VERSION}/sedona-viz-3.0_2.12-${SEDONA_VERSION}.jar"
    "org/datasyslab/geotools-wrapper/1.1.0-25.2/geotools-wrapper-1.1.0-25.2.jar"
)

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

echo "Downloading Sedona ${SEDONA_VERSION} JARs to ${tmpdir}"
for rel_path in "${MAVEN_JARS[@]}"; do
    jar_name="$(basename "${rel_path}")"
    url="${MAVEN_BASE}/${rel_path}"
    echo "  ${jar_name}"
    curl -fsSL "${url}" -o "${tmpdir}/${jar_name}"
done

if [[ -n "${EXTRA_JARS_DIR:-}" && -d "${EXTRA_JARS_DIR}" ]]; then
    echo "Adding extra JARs from ${EXTRA_JARS_DIR}"
    cp "${EXTRA_JARS_DIR}"/*.jar "${tmpdir}/" 2>/dev/null || true
fi

echo "Uploading to ${S3_PREFIX}"
aws s3 sync "${tmpdir}/" "${S3_PREFIX}" --exclude "*" --include "*.jar" --acl bucket-owner-full-control

echo "Done. Objects:"
aws s3 ls "${S3_PREFIX}"
