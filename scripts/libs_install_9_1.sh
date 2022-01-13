#! /bin/bash

# This script is used for initializing clusters dependencies in Databricks
# and it is manually placed inside 5a-artifacts/bi-etl-ejuice

echo "Installing libs"
/databricks/python/bin/pip install amqp==2.6.1
/databricks/python/bin/pip install awscli

aws s3 cp s3://5a-artifacts/bi-etl-ejuice/bi_etl_ejuice-latest-py3-none-any.whl /bi_etl_ejuice-latest-py3-none-any.whl
aws s3 cp s3://5a-artifacts/python-logger/quintoandar_logger-0.8.0-py3-none-any.whl /quintoandar_logger-0.8.0-py3-none-any.whl
aws s3 cp s3://artifacts.s3.data.quintoandar.com.br/inmetro/inmetro-2.0.0-py3-none-any.whl /inmetro-2.0.0-py3-none-any.whl
aws s3 cp s3://5a-artifacts/jars/deequ-1.2.2-spark-3.0.jar /databricks/jars

/databricks/python/bin/pip install /bi_etl_ejuice-latest-py3-none-any.whl
/databricks/python/bin/pip install /quintoandar_logger-0.8.0-py3-none-any.whl
/databricks/python/bin/pip install '/inmetro-2.0.0-py3-none-any.whl[pydeequ]'
