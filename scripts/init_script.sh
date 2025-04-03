#! /bin/bash

spark_jars_path="/databricks/jars"

echo "BEGIN: Modify Spark config settings"
spark_driver_config_file="$DB_HOME/driver/conf/00-spark-plugin-driver-defaults.conf"
spark_driver_config_content="[driver] {
    \"spark.plugins\" = \"ch.cern.CloudFSMetrics,ch.cern.CgroupMetrics,br.com.quintoandar.GangliaMetrics\",
    \"spark.cernSparkPlugin.cloudFsName\" = \"s3a\",
    \"spark.cernSparkPlugin.registerOnDriver\" = \"true\",
    \"spark.extraListeners\" = \"ch.cern.sparkmeasure.FlightRecorderStageMetrics\"
}
"
echo "$spark_driver_config_content" | tee $spark_driver_config_file 1>/dev/null
echo "END: Modify Spark config settings"

echo "BEGIN: Install QuintoAndar internal libs"
/databricks/python/bin/pip install -q awscli

aws s3 cp ${ARTIFACTS_BUCKET}/jars/deequ-2.0.1-spark-3.2.jar $spark_jars_path/deequ-2.0.1-spark-3.2.jar
aws s3 cp ${ARTIFACTS_BUCKET}/jars/spark-measure_2.12-0.21.jar $spark_jars_path/spark-measure_2.12-0.21.jar
aws s3 cp ${ARTIFACTS_BUCKET}/jars/spark-plugins_2.12-0.2.jar $spark_jars_path/spark-plugins_2.12-0.2.jar
aws s3 cp ${ARTIFACTS_BUCKET}/jars/spark-cluster-metrics_2.12-0.1-SNAPSHOT.jar $spark_jars_path/spark-cluster-metrics_2.12-0.1-SNAPSHOT.jar

aws s3 cp ${ARTIFACTS_BUCKET}/bi-etl-ejuice/bi_etl_ejuice-latest-py3-none-any.whl /bi_etl_ejuice-latest-py3-none-any.whl
aws s3 cp ${ARTIFACTS_BUCKET}/python-logger/quintoandar_logger-0.8.0-py3-none-any.whl /quintoandar_logger-0.8.0-py3-none-any.whl
aws s3 cp ${ARTIFACTS_BUCKET}/inmetro/inmetro-2.3.0-py3-none-any.whl /inmetro-2.3.0-py3-none-any.whl

/databricks/python/bin/pip install -q /bi_etl_ejuice-latest-py3-none-any.whl
/databricks/python/bin/pip install -q /quintoandar_logger-0.8.0-py3-none-any.whl
/databricks/python/bin/pip install -q '/inmetro-2.3.0-py3-none-any.whl[pydeequ]'
echo "END: Install QuintoAndar internal libs"
