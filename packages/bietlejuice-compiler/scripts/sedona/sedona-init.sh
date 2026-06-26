#!/bin/bash
#
# Databricks cluster init: install Sedona JARs into /databricks/jars from the artifacts bucket.
# EMR bootstrap: pass artifacts bucket as $1 (spark_env_vars not loaded at bootstrap time).
#
# JARs must be published under:
#   ${ARTIFACTS_BUCKET}/sedona/jars/${SEDONA_VERSION}/*.jar
#
# Use publish_sedona_jars_to_artifacts.sh to populate that prefix (Maven + any extra JARs).
#
# Cluster spark_conf should still set Sedona SQL extensions and Kryo registrator
# (see custom_cluster_with_sedona / emr_cluster_with_sedona in forno_conf.yml / prod_conf.yml).

set -euo pipefail

SEDONA_VERSION="${SEDONA_VERSION:-1.2.1-incubating}"

if [[ -n "${1:-}" ]]; then
    ARTIFACTS_BUCKET="$1"
fi

if [[ -z "${ARTIFACTS_BUCKET:-}" ]]; then
    echo "ERROR: ARTIFACTS_BUCKET is not set (expected s3://artifacts... from cluster spark_env_vars or \$1 on EMR)."
    exit 1
fi

sedona_jars_s3_prefix="${ARTIFACTS_BUCKET}/sedona/jars/${SEDONA_VERSION}/"

echo "BEGIN: Install Sedona ${SEDONA_VERSION} jars from ${sedona_jars_s3_prefix}"

if [[ -d /databricks ]]; then
    spark_jars_path="/databricks/jars"
    /databricks/python/bin/pip install -q awscli
else
    spark_jars_path="/usr/lib/spark/jars"
fi

jar_listing="$(aws s3 ls "${sedona_jars_s3_prefix}" 2>/dev/null | awk '/\.jar$/ {print $4}' || true)"
if [[ -z "${jar_listing}" ]]; then
    echo "ERROR: No .jar objects at ${sedona_jars_s3_prefix}."
    echo "Run packages/bietlejuice-compiler/scripts/publish_sedona_jars_to_artifacts.sh for this version."
    exit 1
fi

while IFS= read -r jar_name; do
    [[ -n "${jar_name}" ]] || continue
    echo "Copying ${jar_name}"
    if [[ -d /databricks ]]; then
        aws s3 cp "${sedona_jars_s3_prefix}${jar_name}" "${spark_jars_path}/${jar_name}"
    else
        staging="/tmp/sedona-${jar_name}"
        aws s3 cp "${sedona_jars_s3_prefix}${jar_name}" "${staging}"
        sudo mkdir -p "${spark_jars_path}"
        sudo cp "${staging}" "${spark_jars_path}/${jar_name}"
        sudo chmod 644 "${spark_jars_path}/${jar_name}"
        rm -f "${staging}"
    fi
done <<< "${jar_listing}"

echo "END: Install Sedona jars (${SEDONA_VERSION})"
