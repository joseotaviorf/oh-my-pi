#!/usr/bin/env bash
# EMR bootstrap for enrich_anonymization (PII scan with Presidio + SpaCy).
# Runs the standard bietlejuice EMR init, then installs Presidio, NumPy, and the
# en_core_web_lg SpaCy model wheel from the artifacts bucket.
#
# Usage: init_script_anonymization.sh <artifacts_bucket> [databricks_s3_bucket] [airflow_dag_id]
# Same arguments as emr_init_script.sh.

set -euo pipefail

TMP_DIR="/tmp"

PRESIDIO_VERSION="${PRESIDIO_VERSION:-2.2.357}"
NUMPY_VERSION="${NUMPY_VERSION:-1.26.4}"
# Match en_core_web_lg-3.7.1; stay on 3.7.x — spacy 3.8+ needs thinc>=8.3.12 with no
# cp39/aarch64 wheels on EMR 7.12 (Python 3.9, Graviton).
SPACY_VERSION="${SPACY_VERSION:-3.7.5}"
SPACY_MODEL_WHL="en_core_web_lg-3.7.1-py3-none-any.whl"

echo "BEGIN: enrich_anonymization EMR bootstrap"

if [ $# -lt 1 ]; then
    echo "Error: This script requires at least 1 argument."
    echo "Usage: $0 <artifacts_bucket> [databricks_s3_bucket] [airflow_dag_id]"
    exit 1
fi

ARTIFACTS_BUCKET="$1"
PIP_EXEC="sudo pip3"

# Pre-download while EMR awscli is intact — emr_init_script.sh pip installs can break
# python-dateutil and we must not call aws after that.
echo "Downloading libraries from S3 into ${TMP_DIR}..."
sudo mkdir -p "${TMP_DIR}/wheels"
sudo chown "$(whoami)" "${TMP_DIR}/wheels"

EMR_INIT_SCRIPT="${TMP_DIR}/emr_init_script.sh"
aws s3 cp "${ARTIFACTS_BUCKET}/bi-etl-ejuice/emr_init_script.sh" "${EMR_INIT_SCRIPT}"
aws s3 cp "${ARTIFACTS_BUCKET}/spacy-models/${SPACY_MODEL_WHL}" \
    "${TMP_DIR}/wheels/${SPACY_MODEL_WHL}"

# Event-log prefix (normally created by emr_init when dag_id is passed).
DATABRICKS_S3_BUCKET="${2:-}"
AIRFLOW_DAG_ID="${3:-}"
if [ -n "${DATABRICKS_S3_BUCKET}" ] && [ -n "${AIRFLOW_DAG_ID}" ]; then
    echo "BEGIN: Create Spark event-log directory"
    aws s3api put-object \
        --bucket "${DATABRICKS_S3_BUCKET}" \
        --key "spark-event-logs-emr/${AIRFLOW_DAG_ID}/" \
        || echo "  WARN: failed to create Spark event-log prefix"
    echo "END: Create Spark event-log directory"
fi

chmod +x "${EMR_INIT_SCRIPT}"
# Omit airflow_dag_id so emr_init_script.sh does NOT install cluster
# custom_libraries (YAML pypi:presidio pulls SpaCy 3.8 → blis source build
# fails on EMR 7.12 Graviton/cp39). Also set SKIP_CUSTOM_LIBRARIES for
# newer emr_init builds that honor the flag even when dag_id is present.
export SKIP_CUSTOM_LIBRARIES=1
"${EMR_INIT_SCRIPT}" "${ARTIFACTS_BUCKET}" "${DATABRICKS_S3_BUCKET}"

echo "BEGIN: Install Presidio / SpaCy anonymization libraries"

ANON_CONSTRAINTS="${TMP_DIR}/anonymization-pip-constraints.txt"
cat >"${ANON_CONSTRAINTS}" <<EOF
numpy==${NUMPY_VERSION}
spacy==${SPACY_VERSION}
EOF

# --only-binary: never fall back to compiling thinc/blis on the cluster.
echo "Installing numpy==${NUMPY_VERSION} and spacy==${SPACY_VERSION} (wheels only)..."
if ! $PIP_EXEC install --no-cache-dir --only-binary=:all: -c "${ANON_CONSTRAINTS}" \
    "numpy==${NUMPY_VERSION}" \
    "spacy==${SPACY_VERSION}"; then
    echo "Error: pip install of numpy/spacy failed (need manylinux aarch64 wheels)."
    exit 1
fi

# presidio-analyzer pulls spacy>=3.8 without a pin; install without deps after spacy 3.7.x.
echo "Installing presidio-analyzer==${PRESIDIO_VERSION} (no-deps)..."
if ! $PIP_EXEC install --no-cache-dir --no-deps "presidio-analyzer==${PRESIDIO_VERSION}"; then
    echo "Error: pip install presidio-analyzer failed."
    exit 1
fi

echo "Installing presidio-analyzer PyPI dependencies (excluding spacy)..."
if ! $PIP_EXEC install --no-cache-dir -c "${ANON_CONSTRAINTS}" \
    'phonenumbers>=8.12' \
    'PyYAML>=6.0.1' \
    'regex' \
    'tldextract>=3.4.4'; then
    echo "Error: pip install of presidio-analyzer dependencies failed."
    exit 1
fi

echo "Installing SpaCy model wheel ${SPACY_MODEL_WHL} (no-deps)..."
if ! $PIP_EXEC install --no-cache-dir --no-deps --ignore-requires-python \
    "${TMP_DIR}/wheels/${SPACY_MODEL_WHL}"; then
    echo "Error: pip install of ${SPACY_MODEL_WHL} failed."
    exit 1
fi

echo "Restoring python-dateutil for awscli compatibility..."
$PIP_EXEC install 'python-dateutil>=2.1,<=2.9.0'

echo "Validating installation..."

$PIP_EXEC show presidio-analyzer
$PIP_EXEC show spacy
$PIP_EXEC show numpy
python3 -c 'import presidio_analyzer; import spacy; spacy.load("en_core_web_lg"); print("anonymization libs OK")'

echo "DONE: enrich_anonymization EMR bootstrap finished."
