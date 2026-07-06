#!/usr/bin/env bash
# EMR bootstrap for CDP ClickHouse ingestion DAGs.
# Runs the standard bietlejuice EMR init, then installs ClickHouse Spark native connector JARs
# (format-based read: spark.read.format("clickhouse")).
#
# Usage: init_script_cdp.sh <artifacts_bucket> [databricks_s3_bucket] [airflow_dag_id]
# Same arguments as emr_init_script.sh.

set -euo pipefail

TMP_DIR="/tmp"

CLICKHOUSE_SPARK_VERSION="${CLICKHOUSE_SPARK_VERSION:-0.10.0}"
CLICKHOUSE_JDBC_VERSION="${CLICKHOUSE_JDBC_VERSION:-0.9.5}"
SPARK_BINARY_VERSION="${SPARK_BINARY_VERSION:-3.5}"
SCALA_BINARY_VERSION="${SCALA_BINARY_VERSION:-2.12}"

CLICKHOUSE_SPARK_JAR="clickhouse-spark-runtime-${SPARK_BINARY_VERSION}_${SCALA_BINARY_VERSION}-${CLICKHOUSE_SPARK_VERSION}.jar"
CLICKHOUSE_JDBC_JAR="clickhouse-jdbc-${CLICKHOUSE_JDBC_VERSION}-all.jar"

MAVEN_SPARK_JAR_URL="https://repo1.maven.org/maven2/com/clickhouse/spark/clickhouse-spark-runtime-${SPARK_BINARY_VERSION}_${SCALA_BINARY_VERSION}/${CLICKHOUSE_SPARK_VERSION}/${CLICKHOUSE_SPARK_JAR}"
MAVEN_JDBC_JAR_URL="https://repo1.maven.org/maven2/com/clickhouse/clickhouse-jdbc/${CLICKHOUSE_JDBC_VERSION}/${CLICKHOUSE_JDBC_JAR}"

if [ $# -lt 1 ]; then
    echo "Error: This script requires at least 1 argument."
    echo "Usage: $0 <artifacts_bucket> [databricks_s3_bucket] [airflow_dag_id]"
    exit 1
fi

ARTIFACTS_BUCKET="$1"

echo "BEGIN: CDP ClickHouse EMR bootstrap"

EMR_INIT_SCRIPT="${TMP_DIR}/emr_init_script.sh"
aws s3 cp "${ARTIFACTS_BUCKET}/bi-etl-ejuice/emr_init_script.sh" "${EMR_INIT_SCRIPT}"
chmod +x "${EMR_INIT_SCRIPT}"
"${EMR_INIT_SCRIPT}" "$@"

echo "BEGIN: Install ClickHouse Spark native connector JARs"

download_clickhouse_jar() {
    local jar_name="$1"
    local maven_url="$2"
    local artifacts_key="jars/${jar_name}"

    if aws s3 cp "${ARTIFACTS_BUCKET}/${artifacts_key}" "${TMP_DIR}/${jar_name}" 2>/dev/null; then
        echo "  Downloaded ${jar_name} from artifacts bucket"
        return 0
    fi

    echo "  ${jar_name} not in artifacts bucket; fetching from Maven Central..."
    curl -fsSL "${maven_url}" -o "${TMP_DIR}/${jar_name}"
}

download_clickhouse_jar "${CLICKHOUSE_SPARK_JAR}" "${MAVEN_SPARK_JAR_URL}"
download_clickhouse_jar "${CLICKHOUSE_JDBC_JAR}" "${MAVEN_JDBC_JAR_URL}"

SPARK_JARS_DIRS="/usr/lib/spark/jars"
PYSPARK_JARS=$(python3 -c "import pyspark; print(pyspark.__path__[0] + '/jars')" 2>/dev/null) \
    && SPARK_JARS_DIRS="${SPARK_JARS_DIRS} ${PYSPARK_JARS}"

for jar in "${CLICKHOUSE_SPARK_JAR}" "${CLICKHOUSE_JDBC_JAR}"; do
    for jdir in ${SPARK_JARS_DIRS}; do
        sudo mkdir -p "${jdir}"
        sudo cp "${TMP_DIR}/${jar}" "${jdir}/${jar}"
        sudo chmod 644 "${jdir}/${jar}"
    done
    echo "  Installed ${jar}"
done

echo "END: CDP ClickHouse EMR bootstrap finished."
