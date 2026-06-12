#!/bin/bash
# Minimal EMR bootstrap: install bi-etl-ejuice + python-logger wheels from the artifacts
# bucket and verify imports. Does not replace scripts/emr_init_script.sh (production).
#
# Usage (same contract as production EMR init): exactly one argument — artifacts bucket base URI:
#   bash emr_init_minimal.sh s3://artifacts.example.com
#
# Delta Python API: pin delta-spark to match the EMR release Delta runtime; adjust if you see
# version mismatches (see scripts/emr_init_script.sh for the full production pin strategy).

set -euo pipefail

TMP_DIR="${TMP_DIR:-/tmp}"
PIP_EXEC="${PIP_EXEC:-sudo pip3}"

if [ "${PROVIDER:-}" = "databricks" ]; then
  echo "This minimal sample targets EMR only; use init_script.sh on Databricks."
  exit 1
fi

if [ $# -ne 1 ]; then
  echo "Usage: $0 <artifacts_bucket>"
  exit 1
fi

ARTIFACTS_BUCKET="$1"

echo "BEGIN: Minimal EMR bootstrap (bi-etl-ejuice + quintoandar-logger)"

sudo mkdir -p "${TMP_DIR}/wheels"
sudo chown "$(whoami)" "${TMP_DIR}/wheels"

aws s3 cp "${ARTIFACTS_BUCKET}/bi-etl-ejuice/bi_etl_ejuice-latest-py3-none-any.whl" \
  "${TMP_DIR}/wheels/bi_etl_ejuice-latest-py3-none-any.whl"
aws s3 cp "${ARTIFACTS_BUCKET}/python-logger/quintoandar_logger-0.8.0-py3-none-any.whl" \
  "${TMP_DIR}/wheels/quintoandar_logger-0.8.0-py3-none-any.whl"

$PIP_EXEC install --upgrade --ignore-installed 'requests==2.32.5' 'urllib3>=1.25.4,<1.27'

echo "Downloading dependency wheels..."
$PIP_EXEC download \
  "${TMP_DIR}/wheels/bi_etl_ejuice-latest-py3-none-any.whl" \
  "${TMP_DIR}/wheels/quintoandar_logger-0.8.0-py3-none-any.whl" \
  --dest "${TMP_DIR}/wheels/" || echo "Some deps may install from source"

echo "Installing wheelhouse (skip EMR-native packages — same idea as scripts/emr_init_script.sh)..."
for f in "${TMP_DIR}/wheels"/*.whl "${TMP_DIR}/wheels"/*.tar.gz; do
  [ -f "$f" ] || continue
  base=$(basename "$f" .whl)
  base=${base%.tar.gz}
  name=$(echo "$base" | sed -E 's/-[0-9]+(\.[0-9]+)*.*//' | tr '_' '-')
  # Never pip-install PySpark from the wheelhouse: EMR ships PySpark matched to its Spark/Delta JVM.
  # bi-etl-ejuice deps may pull a pyspark wheel into TMP_DIR; without this, an edge case where
  # ``pip show pyspark`` fails could overwrite EMR's layout.
  if [ "$name" = "pyspark" ]; then
    echo "  Skip $name (preserve EMR native PySpark)"
  elif [ "$name" = "delta-spark" ]; then
    echo "  Skip $name (preserve EMR native Delta / install pinned below)"
  elif $PIP_EXEC show "$name" &>/dev/null; then
    echo "  Skip $name (already installed)"
  else
    $PIP_EXEC install --no-cache-dir --no-deps "$f"
  fi
done

# Same pin strategy as scripts/emr_init_script.sh for EMR — adjust if Spark/Delta mismatch.
echo "Installing delta-spark Python API..."
$PIP_EXEC install --no-cache-dir 'delta-spark==3.3.2'
$PIP_EXEC install 'urllib3>=1.25.4,<1.27'
$PIP_EXEC install 'python-dateutil>=2.1,<=2.9.0'

echo "Validating imports..."
python3 -c "from bietlejuice.loaders.delta_loader import DeltaLoader; from quintoandar_logger import QuintoAndarLogger; print('ok')"

echo "END: Minimal EMR bootstrap completed."
