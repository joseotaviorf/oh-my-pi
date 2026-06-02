#!/usr/bin/env bash
# EMR / Databricks bootstrap for bietlejuice wheels from S3.
# EMR: pass artifacts bucket as $1 (see forno_conf.yml / prod_conf.yml init_scripts).
# Databricks: set PROVIDER=databricks; wheel S3 steps are skipped (install wheels via UI/CI if needed).

TMP_DIR="/tmp"

DEEQU_JAR_VERSION="${DEEQU_JAR_VERSION:-2.0.8}"
SPARK_VERSION="${SPARK_VERSION:-3.5}"
# Wheel metadata declares Requires-Python >=3.10; EMR default pip3 is 3.9 and installs with
# --ignore-requires-python (validated on EMR 7.12).
INMETRO_VERSION="${INMETRO_VERSION:-4.10.1}"
KAFKA_CLIENTS_JAR="${KAFKA_CLIENTS_JAR:-kafka-clients-3.5.0.jar}"
OPENLINEAGE_JAR="${OPENLINEAGE_JAR:-openlineage-spark_2.12-1.46.0.jar}"
MYSQL_JDBC_JAR="${MYSQL_JDBC_JAR:-mysql-connector-java-8.0.30.jar}"
QUINTOANDAR_LOGGER_WHEEL="${QUINTOANDAR_LOGGER_WHEEL:-quintoandar_logger-0.8.0-py3-none-any.whl}"
REQUESTS_VERSION="${REQUESTS_VERSION:-2.32.5}"
DATABRICKS_SDK_VERSION="${DATABRICKS_SDK_VERSION:-0.102.0}"

echo "BEGIN: Install QuintoAndar internal libs"

if [ "${PROVIDER:-}" = "databricks" ]; then
    echo "PROVIDER=databricks. Using Databricks environment."
    PIP_EXEC="/databricks/python/bin/pip"
    echo "Installing awscli..."
    $PIP_EXEC install -q awscli
else
    echo "Using EMR environment."

    if [ $# -lt 1 ]; then
        echo "Error: This script requires at least 1 argument."
        echo "Usage: $0 <artifacts_bucket> [databricks_s3_bucket] [airflow_dag_id]"
        exit 1
    fi

    ARTIFACTS_BUCKET="$1"
    DATABRICKS_S3_BUCKET="${2:-${DATABRICKS_S3_BUCKET:-}}"
    AIRFLOW_DAG_ID="${3:-${AIRFLOW_DAG_ID:-}}"
    PIP_EXEC="sudo pip3"
    echo "Skipping awscli installation (assumed pre-installed on EMR)."

    if [ -n "$DATABRICKS_S3_BUCKET" ] && [ -n "$AIRFLOW_DAG_ID" ]; then
        echo "BEGIN: Create Spark event-log directory"
        aws s3api put-object \
            --bucket "$DATABRICKS_S3_BUCKET" \
            --key "spark-event-logs-emr/${AIRFLOW_DAG_ID}/" \
            || echo "  WARN: failed to create Spark event-log prefix"
        echo "END: Create Spark event-log directory"
    fi
fi

# --- Wheel download (EMR only; Databricks uses cluster libraries / other path) ---
if [ "${PROVIDER:-}" != "databricks" ]; then
    echo "Downloading libraries from S3 into ${TMP_DIR}..."
    sudo mkdir -p "${TMP_DIR}/wheels"
    sudo chown "$(whoami)" "${TMP_DIR}/wheels"

    aws s3 cp "${ARTIFACTS_BUCKET}/bi-etl-ejuice/bietlejuice_core-latest-py3-none-any.whl" \
        "${TMP_DIR}/wheels/bietlejuice_core-latest-py3-none-any.whl"
    aws s3 cp "${ARTIFACTS_BUCKET}/bi-etl-ejuice/bietlejuice_runtime-latest-py3-none-any.whl" \
        "${TMP_DIR}/wheels/bietlejuice_runtime-latest-py3-none-any.whl"
    aws s3 cp "${ARTIFACTS_BUCKET}/python-logger/${QUINTOANDAR_LOGGER_WHEEL}" \
        "${TMP_DIR}/wheels/${QUINTOANDAR_LOGGER_WHEEL}"
    aws s3 cp "${ARTIFACTS_BUCKET}/inmetro/inmetro-${INMETRO_VERSION}-py3-none-any.whl" \
        "${TMP_DIR}/wheels/inmetro-${INMETRO_VERSION}-py3-none-any.whl"
    
    # Pin urllib3 / requests for awscli before resolving the big stack.
    $PIP_EXEC install --upgrade --ignore-installed \
        "requests==${REQUESTS_VERSION}" 'urllib3>=1.25.4,<1.27'

    echo "Installing quintoandar-logger wheel (with deps)..."
    if ! $PIP_EXEC install --no-cache-dir "${TMP_DIR}/wheels/${QUINTOANDAR_LOGGER_WHEEL}"; then
        echo "Error: pip install quintoandar-logger failed."
        exit 1
    fi

    # Mirrors packages/bietlejuice-runtime [tool.uv].override-dependencies for pip (constraints
    # only narrow the solver; they cannot relax validations-engine's requests==2.28.1 pin).
    EMR_CONSTRAINTS="${TMP_DIR}/emr-pip-constraints.txt"
    cat >"${EMR_CONSTRAINTS}" <<'EOF'
requests>=2.32.3
tenacity>=8.0.1
EOF

    # validations-engine 2.0.0 declares requests==2.28.1; bietlejuice-core needs >=2.32.3.
    # Install it without deps after pinning requests (same effect as uv override-dependencies).
    echo "Installing validations-engine (no-deps; requests already pinned)..."
    if ! $PIP_EXEC install --no-cache-dir --no-deps 'validations-engine==2.0.0'; then
        echo "Error: pip install validations-engine failed."
        exit 1
    fi

    # PyPI deps from bietlejuice-runtime + bietlejuice-core wheels (excluding validations-engine,
    # which is already installed). Keeps one resolver pass under constraints.
    echo "Installing bietlejuice transitive PyPI dependencies (constraints)..."
    if ! $PIP_EXEC install --no-cache-dir -c "${EMR_CONSTRAINTS}" \
        'bs4>=0.0.1' \
        'boto3>=1.37.3' \
        'businesstimedelta' \
        'Cerberus>=1.3.5' \
        'dependency-injector>=4.46.0' \
        'Deprecated>=1.2.18' \
        'defusedxml' \
        'hierarchical-conf==1.0.4' \
        'hive-metastore-client>=1.0.9' \
        'holidays' \
        'importlib-metadata>=1.0.0' \
        'opentelemetry-exporter-otlp-proto-http>=1.22.0' \
        'paramiko' \
        'pendulum' \
        'pymongo>=4.0.0' \
        'PyYAML>=6.0.1' \
        'SQLAlchemy>=1.4.54' \
        'sqlglot>=26.9.0' \
        'trino>=0.305.0' \
        'Unidecode==1.1.1'; then
        echo "Error: pip install of bietlejuice PyPI dependencies failed."
        exit 1
    fi

    # delta-spark declares pyspark; EMR already ships PySpark — install the wheel only (same as runtime pyproject note).
    echo "Installing delta-spark 3.3.1 (no-deps; cluster PySpark)..."
    if ! $PIP_EXEC install --no-cache-dir --no-deps 'delta-spark==3.3.1'; then
        echo "Error: pip install delta-spark failed."
        exit 1
    fi

    echo "Installing bietlejuice core + runtime wheels (no-deps; logger already installed)..."
    if ! $PIP_EXEC install --no-cache-dir --no-deps \
        "${TMP_DIR}/wheels/bietlejuice_core-latest-py3-none-any.whl" \
        "${TMP_DIR}/wheels/bietlejuice_runtime-latest-py3-none-any.whl"; then
        echo "Error: pip install of bietlejuice wheels failed."
        exit 1
    fi

    # Runtime wheel omits psycopg2 (DBR bundles it); EMR does not.
    echo "Installing psycopg2-binary (EMR)..."
    $PIP_EXEC install --no-cache-dir 'psycopg2-binary==2.9.9'
fi

if [ "${PROVIDER:-}" = "databricks" ]; then
    echo "Pinning requests..."
    $PIP_EXEC install --no-cache-dir --ignore-installed "requests==${REQUESTS_VERSION}"
    echo "Installing databricks-sdk for UC REST API sync..."
    $PIP_EXEC install --no-cache-dir "databricks-sdk==${DATABRICKS_SDK_VERSION}"
fi

if [ "${PROVIDER:-}" != "databricks" ]; then
    echo "Downloading JARs from S3..."
    POSTGRES_JDBC_JAR="${POSTGRES_JDBC_JAR:-postgresql-42.7.3.jar}"
    aws s3 cp "${ARTIFACTS_BUCKET}/jars/${POSTGRES_JDBC_JAR}" "${TMP_DIR}/${POSTGRES_JDBC_JAR}"
    for jar in \
        "deequ-${DEEQU_JAR_VERSION}-spark-${SPARK_VERSION}.jar" \
        "spark-measure_2.12-0.21.jar" \
        "spark-plugins_2.12-0.2.jar" \
        "spark-cluster-metrics_2.12-0.1-SNAPSHOT.jar" \
        "${KAFKA_CLIENTS_JAR}" \
        "${MYSQL_JDBC_JAR}" \
        "${OPENLINEAGE_JAR}"; do
        aws s3 cp "${ARTIFACTS_BUCKET}/jars/${jar}" "${TMP_DIR}/${jar}" \
            || echo "  WARN: ${jar} not found in S3, skipping"
    done

    echo "Installing delta-spark 3.3.2 to match EMR 7.12 native Delta (no-deps; cluster PySpark)..."
    $PIP_EXEC install --no-cache-dir --no-deps 'delta-spark==3.3.2'
    echo "Installing databricks-sdk for UC REST API sync..."
    $PIP_EXEC install --no-cache-dir "databricks-sdk==${DATABRICKS_SDK_VERSION}"
    echo "Pinning urllib3 for EMR awscli/botocore compatibility..."
    $PIP_EXEC install 'urllib3>=1.25.4,<1.27'

    echo "Installing inmetro ${INMETRO_VERSION} on EMR Python 3.9 (pydeequ, yamale, typing-extensions)..."
    $PIP_EXEC install --no-cache-dir --no-deps --ignore-requires-python \
        "${TMP_DIR}/wheels/inmetro-${INMETRO_VERSION}-py3-none-any.whl"
    $PIP_EXEC install --no-cache-dir \
        'pydeequ==1.4.0' \
        'yamale==5.2.1' \
        'typing-extensions==4.12.2'

    if ! python3 -c 'import pandas; major, minor, *_ = (int(x) for x in pandas.__version__.split(".")[:2]); raise SystemExit(0 if (major, minor) >= (2, 0) else 1)' 2>/dev/null; then
        echo "Installing pandas>=2.0.0,<3 for inmetro ${INMETRO_VERSION}..."
        $PIP_EXEC install --no-cache-dir 'pandas>=2.0.0,<3'
    fi

    echo "Restoring python-dateutil for awscli compatibility..."
    $PIP_EXEC install 'python-dateutil>=2.1,<=2.9.0'

    SPARK_JARS_DIRS="/usr/lib/spark/jars"
    PYSPARK_JARS=$(python3 -c "import pyspark; print(pyspark.__path__[0] + '/jars')" 2>/dev/null) \
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
        "${MYSQL_JDBC_JAR}" \
        "${OPENLINEAGE_JAR}"; do
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
fi

echo "Validating installation..."

$PIP_EXEC show databricks-sdk
if [ "${PROVIDER:-}" = "databricks" ]; then
    :
else
    $PIP_EXEC show bietlejuice-core
    $PIP_EXEC show bietlejuice-runtime
    $PIP_EXEC show quintoandar-logger
    $PIP_EXEC show inmetro
    python3 -c 'import psycopg2; print("psycopg2", psycopg2.__version__)'
    echo "Smoke-testing inmetro ${INMETRO_VERSION} on python3..."
    python3 -c "import inmetro; from inmetro.config_reader import ConfigReader; import inspect; assert 'content' in inspect.signature(ConfigReader.__init__).parameters; print('inmetro', inmetro.__version__)"
fi

echo "DONE: bootstrap finished."
