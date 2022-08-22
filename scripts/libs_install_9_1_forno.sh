#! /bin/bash

# This script is used for initializing clusters dependencies in Databricks
# and it is manually placed inside 5a-artifacts/bi-etl-ejuice

echo "Installing libs"
pip install amqp==2.6.1
pip install awscli

aws s3 cp s3://artifacts.s3.forno.data.quintoandar.com.br/bi-etl-ejuice/bi_etl_ejuice-forno-py3-none-any.whl /bi_etl_ejuice-forno-py3-none-any.whl
aws s3 cp s3://artifacts.s3.forno.data.quintoandar.com.br/python-logger/quintoandar_logger-0.8.0-py3-none-any.whl /quintoandar_logger-0.8.0-py3-none-any.whl
aws s3 cp s3://artifacts.s3.forno.data.quintoandar.com.br/inmetro/inmetro-forno-py3-none-any.whl /inmetro-forno-py3-none-any.whl
aws s3 cp s3://artifacts.s3.forno.data.quintoandar.com.br/jars/deequ-1.2.2-spark-3.0.jar /databricks/jars

/databricks/python/bin/pip install /bi_etl_ejuice-forno-py3-none-any.whl
/databricks/python/bin/pip install /quintoandar_logger-0.8.0-py3-none-any.whl
/databricks/python/bin/pip install '/inmetro-forno-py3-none-any.whl[pydeequ]'
