#! /bin/bash

spark_jars_path="/databricks/jars"

echo "=== BEGIN: Modify Spark config settings ==="
spark_driver_config_file="$DB_HOME/driver/conf/00-spark-plugin-driver-defaults.conf"
spark_driver_config_content="[driver] {
    \"spark.plugins\" = \"ch.cern.CloudFSMetrics,ch.cern.CgroupMetrics,br.com.quintoandar.GangliaMetrics\",
    \"spark.cernSparkPlugin.cloudFsName\" = \"s3a\",
    \"spark.cernSparkPlugin.registerOnDriver\" = \"true\",
    \"spark.extraListeners\" = \"ch.cern.sparkmeasure.FlightRecorderStageMetrics\"
}
"
echo "$spark_driver_config_content" | tee $spark_driver_config_file 1>/dev/null
echo "=== END: Modify Spark config settings ==="

echo "=== BEGIN: Copying jar files for spark metrics plugins ==="
/databricks/python/bin/pip install -q awscli
aws s3 cp ${ARTIFACTS_BUCKET}/jars/spark-measure_2.12-0.21.jar $spark_jars_path/spark-measure_2.12-0.21.jar
aws s3 cp ${ARTIFACTS_BUCKET}/jars/spark-plugins_2.12-0.2.jar $spark_jars_path/spark-plugins_2.12-0.2.jar
# Custom QuintoAndar plugin
aws s3 cp ${ARTIFACTS_BUCKET}/jars/spark-cluster-metrics_2.12-0.1-SNAPSHOT.jar $spark_jars_path/spark-cluster-metrics_2.12-0.1-SNAPSHOT.jar

echo "=== END: Copying jar files for spark metrics plugins ==="

echo "Finished installing spark metrics plugins at $(date '+%Y-%m-%dT%T.%zZ')"
