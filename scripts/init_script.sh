#! /bin/bash

# This script is used for initializing clusters dependencies in Databricks
# and it is manually placed inside 5a-artifacts/bi-etl-ejuice

echo "BEGIN: Modify Spark config settings"
apt-get install maven -yqq

spark_jars_path="/databricks/jars"
spark_driver_config_file="$DB_HOME/driver/conf/00-spark-plugin-driver-defaults.conf"
spark_driver_config_content="[driver] {
    \"spark.plugins\" = \"ch.cern.CloudFSMetrics,ch.cern.CgroupMetrics\",
    \"spark.cernSparkPlugin.cloudFsName\" = \"s3a\",
    \"spark.cernSparkPlugin.registerOnDriver\" = \"true\",
    \"spark.extraListeners\" = \"ch.cern.sparkmeasure.FlightRecorderStageMetrics\"
}
"
jars=(\
    ch.cern.sparkmeasure:spark-plugins_2.12:0.2\
    ch.cern.sparkmeasure:spark-measure_2.12:0.21\
    com.amazon.deequ:deequ:1.2.2-spark-3.0
)
for artifact in "${jars[@]}"
    do
        mvn dependency:get -q -Dartifact="$artifact"
        mvn dependency:copy -q -Dartifact="$artifact" -DoutputDirectory="$spark_jars_path"
    done

echo "$spark_driver_config_content" | tee $spark_driver_config_file 1>/dev/null
echo "END: Modify Spark config settings"

echo "BEGIN: Installing QuintoAndar internal libs"
/databricks/python/bin/pip install -q awscli

# Here, the script differentiate between environments
# using different buckets.

aws s3 cp ${ARTIFACTS_BUCKET}/bi-etl-ejuice/bi_etl_ejuice-latest-py3-none-any.whl /bi_etl_ejuice-latest-py3-none-any.whl
aws s3 cp ${ARTIFACTS_BUCKET}/python-logger/quintoandar_logger-0.8.0-py3-none-any.whl /quintoandar_logger-0.8.0-py3-none-any.whl
aws s3 cp ${ARTIFACTS_BUCKET}/inmetro/inmetro-2.2.5-py3-none-any.whl /inmetro-2.2.5-py3-none-any.whl

/databricks/python/bin/pip install -q /bi_etl_ejuice-latest-py3-none-any.whl
/databricks/python/bin/pip install -q /quintoandar_logger-0.8.0-py3-none-any.whl
/databricks/python/bin/pip install -q '/inmetro-2.2.5-py3-none-any.whl[pydeequ]'
echo "END: Installing QuintoAndar internal libs"
