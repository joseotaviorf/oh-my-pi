#!/usr/bin/env bash
# DAG-only EMR bootstrap: keep the platform emr_init_script.sh on Python 3.9
# and install Vespúcio into an isolated Python 3.11 target directory instead.
# EMR 7.12 (the default EMR release for this repo) already ships
# /usr/bin/python3.11; the AMI system python3/pip3 remain 3.9.

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <artifacts_bucket>" >&2
    exit 1
fi

ARTIFACTS_BUCKET="${1%/}"
PYTHON_BIN="/usr/bin/python3.11"
PACKAGE_DIR="/opt/vespucio-python311"
WHEEL_PATH="/tmp/vespucio-latest-py3-none-any.whl"

if [ ! -x "${PYTHON_BIN}" ]; then
    echo "Error: ${PYTHON_BIN} is unavailable on this EMR node." >&2
    exit 1
fi

if ! "${PYTHON_BIN}" -m pip --version >/dev/null; then
    echo "Error: pip is unavailable for ${PYTHON_BIN}." >&2
    exit 1
fi

aws s3 cp \
    "${ARTIFACTS_BUCKET}/vespucio/vespucio-latest-py3-none-any.whl" \
    "${WHEEL_PATH}"

sudo rm -rf "${PACKAGE_DIR}"
sudo mkdir -p "${PACKAGE_DIR}"
# Install Vespúcio with deps: runtime Requires-Dist does not include pyspark
# (pyspark/delta-spark are dev extras). --no-deps here would skip shapely,
# Pillow, and the rest of the predictor stack. The smoke check below fails
# the bootstrap if a future wheel starts pulling pyspark into PACKAGE_DIR.
sudo "${PYTHON_BIN}" -m pip install \
    --no-cache-dir \
    --target "${PACKAGE_DIR}" \
    "${WHEEL_PATH}"

# EMR installs delta only into the system python3.9 site-packages, and vespucio
# declares delta-spark as a dev-only requirement, so this target dir has no
# delta. --no-deps keeps delta-spark's pyspark requirement from landing here and
# shadowing the PySpark that EMR matches to its Spark and Delta JVMs.
sudo "${PYTHON_BIN}" -m pip install \
    --no-cache-dir \
    --target "${PACKAGE_DIR}" \
    --no-deps \
    "delta-spark==3.3.2" \
    "importlib_metadata>=1.0.0"

sudo chmod -R a+rX "${PACKAGE_DIR}"

# Spark is not installed until after bootstrap, so check that delta resolves
# without importing it — importing would pull in the absent pyspark and fail.
# pyspark must also be absent from PACKAGE_DIR so PYTHONPATH cannot shadow
# the PySpark EMR binds to its Spark/Delta JVMs.
PYTHONPATH="${PACKAGE_DIR}" "${PYTHON_BIN}" -c \
    "import sys, importlib.util, vespucio
assert sys.version_info[:2] == (3, 11)
assert importlib.util.find_spec('delta') is not None, 'delta missing from ${PACKAGE_DIR}'
assert importlib.util.find_spec('pyspark') is None, 'pyspark must not land in ${PACKAGE_DIR}'"
