#! /bin/bash

# Definir valores padrão para variáveis

DEEQU_JAR_VERSION="${DEEQU_JAR_VERSION:-2.0.1}"
SPARK_VERSION="${SPARK_VERSION:-3.2}"
INMETRO_VERSION="${INMETRO_VERSION:-2.3.0}"

spark_jars_path="/databricks/jars"

echo "BEGIN: Modify Spark config settings"
spark_driver_config_file="$DB_HOME/driver/conf/00-spark-plugin-driver-defaults.conf"
spark_driver_config_content="[driver] {
    \"spark.plugins\" = \"ch.cern.CloudFSMetrics,ch.cern.CgroupMetrics,br.com.quintoandar.GangliaMetrics\",
    \"spark.cernSparkPlugin.cloudFsName\" = \"s3a\",
    \"spark.cernSparkPlugin.registerOnDriver\" = \"true\",
    # TODO(DPLT-927): remove once Spark event log pipeline is validated stable; superseded by spark.eventLog.* in cluster config.
    \"spark.extraListeners\" = \"ch.cern.sparkmeasure.FlightRecorderStageMetrics\"
}
"
echo "$spark_driver_config_content" | tee $spark_driver_config_file 1>/dev/null
echo "END: Modify Spark config settings"

echo "BEGIN: Install QuintoAndar internal libs"
/databricks/python/bin/pip install -q awscli

if [ -n "$DATABRICKS_S3_BUCKET" ] && [ -n "$AIRFLOW_DAG_ID" ]; then
  echo "BEGIN: Create Spark event-log directory"
  aws s3api put-object \
    --bucket "$DATABRICKS_S3_BUCKET" \
    --key "spark-event-logs/$AIRFLOW_DAG_ID/"
  echo "END: Create Spark event-log directory"
fi

aws s3 cp ${ARTIFACTS_BUCKET}/jars/deequ-${DEEQU_JAR_VERSION}-spark-${SPARK_VERSION}.jar $spark_jars_path/deequ-${DEEQU_JAR_VERSION}-spark-${SPARK_VERSION}.jar
aws s3 cp ${ARTIFACTS_BUCKET}/jars/spark-measure_2.12-0.21.jar $spark_jars_path/spark-measure_2.12-0.21.jar
aws s3 cp ${ARTIFACTS_BUCKET}/jars/spark-plugins_2.12-0.2.jar $spark_jars_path/spark-plugins_2.12-0.2.jar
aws s3 cp ${ARTIFACTS_BUCKET}/jars/spark-cluster-metrics_2.12-0.1-SNAPSHOT.jar $spark_jars_path/spark-cluster-metrics_2.12-0.1-SNAPSHOT.jar

aws s3 cp ${ARTIFACTS_BUCKET}/python-logger/quintoandar_logger-0.8.0-py3-none-any.whl /quintoandar_logger-0.8.0-py3-none-any.whl
aws s3 cp ${ARTIFACTS_BUCKET}/inmetro/inmetro-${INMETRO_VERSION}-py3-none-any.whl /inmetro-${INMETRO_VERSION}-py3-none-any.whl

/databricks/python/bin/pip install --no-cache-dir \
    /quintoandar_logger-0.8.0-py3-none-any.whl \
    "/inmetro-${INMETRO_VERSION}-py3-none-any.whl[pydeequ]"
    
echo "END: Install QuintoAndar internal libs"
