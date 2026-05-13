#!/usr/bin/env bash
# EMR cluster bootstrap only. Databricks installs libraries via default_libraries / cluster
# policies (see .woodpecker/release.yml). This script is uploaded to the artifacts bucket and
# referenced from Airflow EMR configs (forno_conf / prod_conf).
#
# Python packages are installed with Astral uv (pinned) for fast resolution and wheel-first
# installs vs. the previous pip download + per-wheel pip install path.
#
# Usage: emr_init_script.sh <artifacts_bucket_base>
# Example arg: s3://artifacts.s3.forno.data.quintoandar.com.br

TMP_DIR="/tmp"

# Pin for reproducible bootstrap (bump intentionally when adopting new uv behavior).
UV_VERSION="${UV_VERSION:-0.11.14}"

DEEQU_JAR_VERSION="${DEEQU_JAR_VERSION:-2.0.8}"
SPARK_VERSION="${SPARK_VERSION:-3.5}"
# S3 key segment only: .../inmetro/inmetro-${INMETRO_VERSION}-py3-none-any.whl
# (embedded wheel METADATA Version may differ; install uses UV_SKIP_WHEEL_FILENAME_CHECK=1.)
INMETRO_VERSION="${INMETRO_VERSION:-2.3.0}"
KAFKA_CLIENTS_JAR="${KAFKA_CLIENTS_JAR:-kafka-clients-3.5.0.jar}"
MYSQL_JDBC_JAR="${MYSQL_JDBC_JAR:-mysql-connector-java-8.0.30.jar}"

echo "BEGIN: Install QuintoAndar internal libs (EMR, uv ${UV_VERSION})"

if [ "$#" -ne 1 ]; then
    echo "Error: This script requires exactly 1 argument."
    echo "Usage: $0 <artifacts_bucket>"
    exit 1
fi

ARTIFACTS_BUCKET="$1"

PYTHON_BIN="$(command -v python3)"
if [ -z "$PYTHON_BIN" ]; then
    echo "Error: python3 not found on PATH."
    exit 1
fi
echo "Using python: ${PYTHON_BIN}"

echo "Installing uv ${UV_VERSION}..."
# Install into TMP (always writable). Bootstrap often runs as hadoop; see:
# https://docs.astral.sh/uv/reference/installer/ (UV_UNMANAGED_INSTALL)
#
# EMR nodes often cannot reach astral.sh / GitHub. Host artifacts in the same bucket as wheels:
#
#   Fully offline (recommended): copy the Linux x86_64 uv binary from the GitHub release asset
#   (e.g. unpack uv-x86_64-unknown-linux-gnu.tar.gz) to:
#     ${ARTIFACTS_BUCKET}/bi-etl-ejuice/uv/uv
#
#   Or host the official install script only (still needs egress to fetch the uv tarball unless
#   you set UV_DOWNLOAD_URL in the cluster env to an HTTPS mirror of the release files):
#     ${ARTIFACTS_BUCKET}/bi-etl-ejuice/uv/install-${UV_VERSION}.sh
#   Source: curl -fsSL "https://astral.sh/uv/${UV_VERSION}/install.sh" -o install-${UV_VERSION}.sh
#
# Do not pipe curl into sh: download to a file, run it, require success + a real binary.
UV_S3_PREFIX="${ARTIFACTS_BUCKET}/bi-etl-ejuice/uv"
UV_INSTALL_ROOT="${TMP_DIR}/quintoandar-uv"
UV_INSTALL_SCRIPT="${TMP_DIR}/uv-install-${UV_VERSION}.sh"
UV_BIN="${UV_INSTALL_ROOT}/uv"

rm -rf "${UV_INSTALL_ROOT}"
mkdir -p "${UV_INSTALL_ROOT}"

if aws s3 cp "${UV_S3_PREFIX}/uv" "${UV_BIN}" 2>/dev/null; then
    echo "Using uv binary from S3: ${UV_S3_PREFIX}/uv"
    chmod +x "${UV_BIN}"
elif aws s3 cp "${UV_S3_PREFIX}/install-${UV_VERSION}.sh" "${UV_INSTALL_SCRIPT}" 2>/dev/null; then
    echo "Using uv install script from S3: ${UV_S3_PREFIX}/install-${UV_VERSION}.sh"
    if ! env UV_UNMANAGED_INSTALL="${UV_INSTALL_ROOT}" UV_NO_MODIFY_PATH=1 sh "${UV_INSTALL_SCRIPT}"; then
        echo "Error: uv install script exited non-zero (release download may be blocked; use S3 uv binary instead)."
        exit 1
    fi
    rm -f "${UV_INSTALL_SCRIPT}"
elif curl -fsSL "https://astral.sh/uv/${UV_VERSION}/install.sh" -o "${UV_INSTALL_SCRIPT}"; then
    echo "Using uv install script from astral.sh (fallback)."
    if ! env UV_UNMANAGED_INSTALL="${UV_INSTALL_ROOT}" UV_NO_MODIFY_PATH=1 sh "${UV_INSTALL_SCRIPT}"; then
        echo "Error: uv install script exited non-zero (check network access to GitHub releases)."
        exit 1
    fi
    rm -f "${UV_INSTALL_SCRIPT}"
else
    echo "Error: could not obtain uv (tried S3 ${UV_S3_PREFIX}/uv, S3 install script, then astral.sh)."
    echo "Upload ${UV_S3_PREFIX}/uv (binary) or ${UV_S3_PREFIX}/install-${UV_VERSION}.sh to the artifacts bucket."
    exit 1
fi

if [ ! -x "${UV_BIN}" ]; then
    echo "Error: uv binary not found or not executable at ${UV_BIN}."
    ls -la "${UV_INSTALL_ROOT}" 2>/dev/null || true
    exit 1
fi

# System site-packages on EMR; --break-system-packages matches prior sudo pip3 behavior when
# the interpreter is EXTERNALLY-MANAGED. Use sudo when not root (same as historical sudo pip3).
# UV_LINK_MODE=copy: cache under /tmp and target /usr are different filesystems — avoids noisy
# hardlink fallback warnings.
run_uv() {
    if [ "$(id -u)" -eq 0 ]; then
        env UV_LINK_MODE=copy "${UV_BIN}" "$@"
    else
        sudo env UV_LINK_MODE=copy "${UV_BIN}" "$@"
    fi
}

uv_pip_install() {
    run_uv pip install --system --python "${PYTHON_BIN}" --break-system-packages --no-cache "$@"
}

# EMR nodes often run concurrent package activity (bootstrap steps, agents). RPM then fails with
# "can't create transaction lock on /var/lib/rpm/.rpm.lock (Resource temporarily unavailable)".
# Retry only on lock-style errors; surface other failures immediately.
rpm_install_with_lock_retry() {
    local max_attempts="${RPM_INSTALL_MAX_ATTEMPTS:-48}"
    local delay="${RPM_INSTALL_RETRY_SLEEP_SEC:-10}"
    local max_delay="${RPM_INSTALL_RETRY_MAX_SLEEP_SEC:-60}"
    local attempt=0
    local log

    while [ "$attempt" -lt "$max_attempts" ]; do
        attempt=$((attempt + 1))
        log="$(mktemp "${TMP_DIR}/rpm-install.XXXXXX")"
        if "$@" >"${log}" 2>&1; then
            rm -f "${log}"
            return 0
        fi
        # Mid-transaction failures still print ".rpm.lock" / "transaction lock" / "Could not run
        # transaction" when another writer holds the db — retry with backoff (EMR agents, parallel
        # bootstrap).
        if grep -qiE \
            'transaction lock|\.rpm\.lock|Resource temporarily unavailable|Another app is currently holding the yum lock|Could not get lock|Could not run transaction' \
            "${log}"; then
            echo "RPM/dnf/yum contention (attempt ${attempt}/${max_attempts}); retrying in ${delay}s..." >&2
            tail -n 12 "${log}" >&2 || true
            rm -f "${log}"
            sleep "${delay}"
            delay=$((delay + 5))
            if [ "${delay}" -gt "${max_delay}" ]; then
                delay="${max_delay}"
            fi
            continue
        fi
        cat "${log}" >&2
        rm -f "${log}"
        return 1
    done
    echo "Error: exhausted ${max_attempts} attempts waiting for RPM/dnf: $*" >&2
    return 1
}

# EMR AMIs ship the Python runtime but often not development headers; sdists (e.g. spacy if no
# matching wheel, thrift) need Python.h + gcc.
ensure_python_headers_for_sdist_builds() {
    if "${PYTHON_BIN}" - <<'PY'
import pathlib
import sys
import sysconfig

inc = sysconfig.get_path("include")
if pathlib.Path(inc, "Python.h").is_file():
    sys.exit(0)
sys.exit(1)
PY
    then
        _inc="$("${PYTHON_BIN}" -c 'import sysconfig; print(sysconfig.get_path("include"))')"
        echo "Python.h already available under ${_inc}."
        return 0
    fi
    echo "Installing gcc and python3-devel (provides Python.h for C-extension sdists)..."
    if command -v dnf >/dev/null 2>&1; then
        rpm_install_with_lock_retry sudo dnf install -y gcc python3-devel || {
            echo "Error: dnf install gcc python3-devel failed."
            exit 1
        }
    elif command -v yum >/dev/null 2>&1; then
        if ! rpm_install_with_lock_retry sudo yum install -y gcc python3-devel; then
            rpm_install_with_lock_retry sudo yum install -y gcc python39-devel || {
                echo "Error: yum install python3-devel / python39-devel failed."
                exit 1
            }
        fi
    else
        echo "Error: Python.h not found and neither dnf nor yum is available."
        exit 1
    fi
    if ! "${PYTHON_BIN}" - <<'PY'
import pathlib
import sys
import sysconfig

inc = sysconfig.get_path("include")
if pathlib.Path(inc, "Python.h").is_file():
    sys.exit(0)
sys.exit(1)
PY
    then
        echo "Error: Python.h still missing after installing python3-devel (wrong interpreter?)."
        exit 1
    fi
}

# Artifacts ship bietlejuice_*-latest-*.whl (CI rename). uv requires a PEP 440 version in the
# wheel filename; copy to {name}-{Version-from-METADATA}-py3-none-any.whl before install.
canonical_pep440_wheel() {
    local src="$1"
    "${PYTHON_BIN}" - "$src" <<'PY'
import email.parser
import pathlib
import shutil
import sys
import zipfile

src = pathlib.Path(sys.argv[1])
if "latest" not in src.name:
    print(src)
    raise SystemExit(0)
parts = src.stem.split("-")
tags = "-".join(parts[-3:])
with zipfile.ZipFile(src) as z:
    meta_name = next(
        n for n in z.namelist() if ".dist-info/" in n and n.endswith("METADATA")
    )
    msg = email.parser.Parser().parsestr(z.read(meta_name).decode())
name = msg["Name"].replace("-", "_")
ver = msg["Version"].strip()
out = src.parent / f"{name}-{ver}-{tags}.whl"
if out.resolve() != src.resolve():
    shutil.copy2(src, out)
    print(f"Normalized wheel for uv: {src.name} -> {out.name}", file=sys.stderr)
print(out)
PY
}

uv_pip_install_inmetro_wheel() {
    # Published inmetro wheel: filename version can disagree with METADATA (uv treats that as
    # malformed unless skipped). We do not require republishing the artifact; runtime uses
    # metadata inside the wheel. See uv PR #16046 (UV_SKIP_WHEEL_FILENAME_CHECK).
    if [ "$(id -u)" -eq 0 ]; then
        env UV_LINK_MODE=copy UV_SKIP_WHEEL_FILENAME_CHECK=1 "${UV_BIN}" pip install \
            --system --python "${PYTHON_BIN}" --break-system-packages --no-cache --no-deps "$@"
    else
        sudo env UV_LINK_MODE=copy UV_SKIP_WHEEL_FILENAME_CHECK=1 "${UV_BIN}" pip install \
            --system --python "${PYTHON_BIN}" --break-system-packages --no-cache --no-deps "$@"
    fi
}

echo "Downloading internal wheels from S3 into ${TMP_DIR}..."

sudo mkdir -p "${TMP_DIR}/wheels"
sudo chown "$(whoami)" "${TMP_DIR}/wheels"

# bietlejuice is published as two wheels: core (config, base utilities) and runtime
# (Spark job machinery). Spark workers need both.
aws s3 cp "${ARTIFACTS_BUCKET}/bi-etl-ejuice/bietlejuice_core-latest-py3-none-any.whl" \
    "${TMP_DIR}/wheels/bietlejuice_core-latest-py3-none-any.whl"
aws s3 cp "${ARTIFACTS_BUCKET}/bi-etl-ejuice/bietlejuice_runtime-latest-py3-none-any.whl" \
    "${TMP_DIR}/wheels/bietlejuice_runtime-latest-py3-none-any.whl"
aws s3 cp "${ARTIFACTS_BUCKET}/python-logger/quintoandar_logger-0.8.0-py3-none-any.whl" \
    "${TMP_DIR}/wheels/quintoandar_logger-0.8.0-py3-none-any.whl"
aws s3 cp "${ARTIFACTS_BUCKET}/inmetro/inmetro-${INMETRO_VERSION}-py3-none-any.whl" \
    "${TMP_DIR}/wheels/inmetro-${INMETRO_VERSION}-py3-none-any.whl"

CORE_WHL=$(canonical_pep440_wheel "${TMP_DIR}/wheels/bietlejuice_core-latest-py3-none-any.whl")
RUNTIME_WHL=$(canonical_pep440_wheel "${TMP_DIR}/wheels/bietlejuice_runtime-latest-py3-none-any.whl")

# Constrain urllib3 so we do not conflict with pre-installed awscli/botocore on EMR.
echo "Pinning requests / urllib3 for awscli compatibility..."
uv_pip_install --upgrade 'requests==2.32.5' 'urllib3>=1.25.4,<1.27'

# Install bietlejuice stack + transitive deps in one resolver pass (replaces pip download +
# per-wheel pip install --no-deps). bietlejuice-runtime pins delta-spark==3.3.1 for DBR; on EMR
# the JVM is 3.3.2-amzn-1 — override to the matching Python package.
#
# Mirror key lines from packages/bietlejuice-runtime/pyproject.toml [tool.uv].override-dependencies
# (not embedded in published wheels). Do not add quintoandar-logger here: that override makes uv
# resolve it from the index, but the package is private — we pass the wheel on the command line.
#
# --only-binary blis,spacy,thinc: prefer wheels for the spaCy stack (avoids huge sdist builds when
# wheels exist). thrift often has no wheel — still builds from sdist; needs python3-devel + gcc.
ensure_python_headers_for_sdist_builds
echo "Installing bietlejuice + logger + runtime dependencies (uv)..."
OVERRIDES_FILE="${TMP_DIR}/emr-uv-overrides.txt"
cat >"${OVERRIDES_FILE}" <<'EOF'
delta-spark==3.3.2
requests>=2.32.3
tenacity>=8.0.1
EOF
# These overrides are unchanged from the validations-engine / delta / API-client pin fixes;
# --only-binary … is an extra constraint on the same install, not a replacement for --overrides.

if ! uv_pip_install \
    --only-binary blis \
    --only-binary spacy \
    --only-binary thinc \
    --overrides "${OVERRIDES_FILE}" \
    "${CORE_WHL}" \
    "${RUNTIME_WHL}" \
    "${TMP_DIR}/wheels/quintoandar_logger-0.8.0-py3-none-any.whl"; then
    echo "Error: failed to install bietlejuice stack (see uv resolver output above)."
    exit 1
fi

# bietlejuice.clients.db_clients.postgres_client imports psycopg2; runtime wheel omits it from
# Requires-Dist because DBR pre-installs psycopg2. EMR does not — install the binary wheel (no
# system libpq build). Pin aligned with packages/bietlejuice-runtime/envs/dbr-16-4/pyproject.toml.
echo "Installing psycopg2-binary (EMR; not bundled like DBR)..."
uv_pip_install 'psycopg2-binary==2.9.9'

echo "Downloading JARs from S3..."
POSTGRES_JDBC_JAR="${POSTGRES_JDBC_JAR:-postgresql-42.7.3.jar}"
aws s3 cp "${ARTIFACTS_BUCKET}/jars/${POSTGRES_JDBC_JAR}" "${TMP_DIR}/${POSTGRES_JDBC_JAR}"
for jar in \
    "deequ-${DEEQU_JAR_VERSION}-spark-${SPARK_VERSION}.jar" \
    "spark-measure_2.12-0.21.jar" \
    "spark-plugins_2.12-0.2.jar" \
    "spark-cluster-metrics_2.12-0.1-SNAPSHOT.jar" \
    "${KAFKA_CLIENTS_JAR}" \
    "${MYSQL_JDBC_JAR}"; do
    aws s3 cp "${ARTIFACTS_BUCKET}/jars/${jar}" "${TMP_DIR}/${jar}" \
        || echo "  WARN: ${jar} not found in S3, skipping"
done

echo "Ensuring delta-spark 3.3.2 (EMR 7.12 native Delta JVM)..."
uv_pip_install 'delta-spark==3.3.2'

echo "Installing databricks-sdk for UC REST API sync..."
uv_pip_install 'databricks-sdk'

echo "Pinning urllib3 for EMR awscli/botocore compatibility..."
uv_pip_install 'urllib3>=1.25.4,<1.27'

echo "Installing inmetro + missing deps (pydeequ, yamale)..."
echo "  inmetro: installing with UV_SKIP_WHEEL_FILENAME_CHECK=1 (filename vs METADATA mismatch is OK)."
uv_pip_install_inmetro_wheel "${TMP_DIR}/wheels/inmetro-${INMETRO_VERSION}-py3-none-any.whl"
uv_pip_install 'pydeequ==1.4.0' 'yamale==5.2.1'

echo "Restoring python-dateutil for awscli compatibility..."
uv_pip_install 'python-dateutil>=2.1,<=2.9.0'

SPARK_JARS_DIRS="/usr/lib/spark/jars"
PYSPARK_JARS=$("${PYTHON_BIN}" -c "import pyspark; print(pyspark.__path__[0] + '/jars')" 2>/dev/null) \
    && SPARK_JARS_DIRS="${SPARK_JARS_DIRS} ${PYSPARK_JARS}"

echo "Installing PostgreSQL JDBC driver into Spark classpath..."
for jdir in ${SPARK_JARS_DIRS}; do
    sudo mkdir -p "${jdir}"
    sudo cp "${TMP_DIR}/${POSTGRES_JDBC_JAR}" "${jdir}/${POSTGRES_JDBC_JAR}"
    sudo chmod 644 "${jdir}/${POSTGRES_JDBC_JAR}"
    echo "  PostgreSQL JDBC installed at ${jdir}/${POSTGRES_JDBC_JAR}"
done

echo "Installing data-quality, Kafka and MySQL JARs into Spark classpath..."
for jar in \
    "deequ-${DEEQU_JAR_VERSION}-spark-${SPARK_VERSION}.jar" \
    "spark-measure_2.12-0.21.jar" \
    "spark-plugins_2.12-0.2.jar" \
    "spark-cluster-metrics_2.12-0.1-SNAPSHOT.jar" \
    "${KAFKA_CLIENTS_JAR}" \
    "${MYSQL_JDBC_JAR}"; do
    if [ -f "${TMP_DIR}/${jar}" ]; then
        for jdir in ${SPARK_JARS_DIRS}; do
            sudo cp "${TMP_DIR}/${jar}" "${jdir}/${jar}"
            sudo chmod 644 "${jdir}/${jar}"
        done
        echo "  Installed ${jar}"
    else
        echo "  WARN: ${jar} not downloaded, skipping"
    fi
done

echo "Validating installation..."

run_uv pip show bietlejuice-core
run_uv pip show bietlejuice-runtime
run_uv pip show quintoandar-logger
run_uv pip show inmetro
"${PYTHON_BIN}" -c 'import psycopg2; print("psycopg2", psycopg2.__version__)'
