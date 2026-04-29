TMP_DIR="/tmp"

DEEQU_JAR_VERSION="${DEEQU_JAR_VERSION:-2.0.8}"
SPARK_VERSION="${SPARK_VERSION:-3.5}"
INMETRO_VERSION="${INMETRO_VERSION:-2.3.0}"
KAFKA_CLIENTS_JAR="${KAFKA_CLIENTS_JAR:-kafka-clients-3.5.0.jar}"
MYSQL_JDBC_JAR="${MYSQL_JDBC_JAR:-mysql-connector-java-8.0.30.jar}"

echo "BEGIN: Install QuintoAndar internal libs"

# Check the PROVIDER environment variable
if [ "$PROVIDER" = "databricks" ]; then
    echo "PROVIDER=databricks. Using Databricks environment."
    # Define the specific pip executable
    PIP_EXEC="/databricks/python/bin/pip"

    # Install awscli as required
    echo "Installing awscli..."
    $PIP_EXEC install -q awscli

else
    echo "Using EMR environment."

    if [ $# -ne 1 ]; then
        echo "Error: This script requires exactly 1 argument."
        echo "Usage: $0 <artifacts_bucket>"
        exit 1 # Exit with an error status
    fi

    ARTIFACTS_BUCKET=$1

    # Use the default pip executable in the system's PATH
    PIP_EXEC="sudo pip3"

    # Skip awscli installation, as it's assumed to be pre-installed on EMR
    echo "Skipping awscli installation (assumed pre-installed)."
fi

# --- Common Steps ---
# These steps run for both 'databricks' and 'emr'

# Download the wheels using the aws cli
echo "Downloading libraries from S3 into $TMP_DIR..."

sudo mkdir -p $TMP_DIR/wheels
sudo chown $(whoami) $TMP_DIR/wheels

aws s3 cp ${ARTIFACTS_BUCKET}/bi-etl-ejuice/bi_etl_ejuice-latest-py3-none-any.whl $TMP_DIR/wheels/bi_etl_ejuice-latest-py3-none-any.whl
aws s3 cp ${ARTIFACTS_BUCKET}/python-logger/quintoandar_logger-0.8.0-py3-none-any.whl $TMP_DIR/wheels/quintoandar_logger-0.8.0-py3-none-any.whl
aws s3 cp ${ARTIFACTS_BUCKET}/inmetro/inmetro-${INMETRO_VERSION}-py3-none-any.whl $TMP_DIR/wheels/inmetro-${INMETRO_VERSION}-py3-none-any.whl

# On EMR, constrain urllib3 so we don't conflict with pre-installed awscli/botocore
if [ "$PROVIDER" = "databricks" ]; then
    $PIP_EXEC install --upgrade --ignore-installed requests==2.32.5
else
    $PIP_EXEC install --upgrade --ignore-installed 'requests==2.32.5' 'urllib3>=1.25.4,<1.27'
fi

# Download dependencies (allow source fallback)
# --------------------------------------------------
echo "Downloading dependencies of internal wheels..."
$PIP_EXEC download \
  "$TMP_DIR/wheels/bi_etl_ejuice-latest-py3-none-any.whl" \
  "$TMP_DIR/wheels/quintoandar_logger-0.8.0-py3-none-any.whl" \
  --dest "$TMP_DIR/wheels/" || echo "Some deps will be installed from source"

# --------------------------------------------------
# Install from wheelhouse: skip packages already installed (don't overwrite EMR's pyspark, etc.)
# --------------------------------------------------
echo "Installing from wheelhouse (skipping already-installed packages)..."
for f in $TMP_DIR/wheels/*.whl $TMP_DIR/wheels/*.tar.gz; do
    [ -f "$f" ] || continue
    # Get package name: wheel is name-version-....whl, sdist is name-version.tar.gz
    base=$(basename "$f" .whl)
    base=${base%.tar.gz}
    name=$(echo "$base" | sed -E 's/-[0-9]+(\.[0-9]+)*.*//' | tr '_' '-')
    if [ "$PROVIDER" != "databricks" ] && [ "$name" = "delta-spark" ]; then
        echo "  Skip $name (preserve EMR native Delta)"
    elif $PIP_EXEC show "$name" &>/dev/null; then
        echo "  Skip $name (already installed)"
    else
        $PIP_EXEC install --no-cache-dir --no-deps "$f"
    fi
done

# On EMR, restore delta-spark to match the native JVM Delta version (3.3.2-amzn-1)
# The wheel's old dependency (2.3.x) gets skipped in the install loop above,
# but we need the Python API — install the exact matching version.
if [ "$PROVIDER" != "databricks" ]; then
    # --- Download ALL JARs from S3 while aws CLI still works ---
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

    # --- pip installs (may break aws CLI via python-dateutil upgrade) ---
    echo "Installing delta-spark 3.3.2 to match EMR 7.12 native Delta..."
    $PIP_EXEC install --no-cache-dir 'delta-spark==3.3.2'
    echo "Installing databricks-sdk for UC REST API sync..."
    $PIP_EXEC install --no-cache-dir 'databricks-sdk'
    echo "Pinning urllib3 for EMR awscli/botocore compatibility..."
    $PIP_EXEC install 'urllib3>=1.25.4,<1.27'

    echo "Installing inmetro + missing deps (pydeequ, yamale)..."
    $PIP_EXEC install --no-cache-dir --no-deps \
        "$TMP_DIR/wheels/inmetro-${INMETRO_VERSION}-py3-none-any.whl"
    $PIP_EXEC install --no-cache-dir 'pydeequ==1.4.0' 'yamale==5.2.1'

    # Restore python-dateutil to a version compatible with awscli
    echo "Restoring python-dateutil for awscli compatibility..."
    $PIP_EXEC install 'python-dateutil>=2.1,<=2.9.0'

    # --- Copy JARs into Spark classpath (EMR native + pip-installed pyspark) ---
    SPARK_JARS_DIRS="/usr/lib/spark/jars"
    PYSPARK_JARS=$(python3 -c "import pyspark; print(pyspark.__path__[0] + '/jars')" 2>/dev/null) \
        && SPARK_JARS_DIRS="$SPARK_JARS_DIRS $PYSPARK_JARS"

    echo "Installing PostgreSQL JDBC driver into Spark classpath..."
    for jdir in $SPARK_JARS_DIRS; do
        sudo mkdir -p "$jdir"
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
            for jdir in $SPARK_JARS_DIRS; do
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

$PIP_EXEC show bi-etl-ejuice
$PIP_EXEC show quintoandar-logger
$PIP_EXEC show inmetro
