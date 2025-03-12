#! /bin/bash

# The code below was inserted to solve a problem during on-call. Databricks VMs was caching old mirrors, so the Maven
# installation wasn't working. The link below provides more details about the solution.
# https://community.databricks.com/t5/data-engineering/library-installation-fails-with-mirror-sync-issue/td-p/12429

echo "BEGIN: Refreshing VM mirrors"

r="deb http://archive.ubuntu.com/ubuntu/ focal-updates main restricted"
add-apt-repository --remove "${r}"
r="deb http://archive.ubuntu.com/ubuntu/ focal-updates universe"
add-apt-repository --remove "${r}"
r="deb http://security.ubuntu.com/ubuntu/ focal-security main restricted"
add-apt-repository --remove "${r}"

sudo apt-get update --fix-missing
echo "END: Refreshing VM mirrors"

echo "BEGIN: Install Spark external JARs with Maven"
apt-get install maven -yqq

spark_jars_path="/databricks/jars"
jars=(\
    ch.cern.sparkmeasure:spark-plugins_2.12:0.2\
    ch.cern.sparkmeasure:spark-measure_2.12:0.21\
    com.amazon.deequ:deequ:2.0.1-spark-3.2
)
for artifact in "${jars[@]}"
    do
        mvn dependency:get -q -Dartifact="$artifact"
        mvn dependency:copy -q -Dartifact="$artifact" -DoutputDirectory="$spark_jars_path"
    done
echo "END: Install Spark external JARs with Maven"

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

aws s3 cp ${ARTIFACTS_BUCKET}/jars/spark-cluster-metrics_2.12-0.1-SNAPSHOT.jar $spark_jars_path/spark-cluster-metrics_2.12-0.1-SNAPSHOT.jar
aws s3 cp ${ARTIFACTS_BUCKET}/bi-etl-ejuice/bi_etl_ejuice-latest-py3-none-any.whl /bi_etl_ejuice-latest-py3-none-any.whl
aws s3 cp ${ARTIFACTS_BUCKET}/python-logger/quintoandar_logger-0.8.0-py3-none-any.whl /quintoandar_logger-0.8.0-py3-none-any.whl
aws s3 cp ${ARTIFACTS_BUCKET}/inmetro/inmetro-4.7.1-py3-none-any.whl /inmetro-4.7.1-py3-none-any.whl

/databricks/python/bin/pip install -q /bi_etl_ejuice-latest-py3-none-any.whl
/databricks/python/bin/pip install -q /quintoandar_logger-0.8.0-py3-none-any.whl
/databricks/python/bin/pip install -q '/inmetro-4.7.1-py3-none-any.whl[pydeequ]'
echo "END: Install QuintoAndar internal libs"
