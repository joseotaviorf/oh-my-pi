# Databricks notebook source
dbutils.library.installPyPI("boto3", version="1.9.156")

# COMMAND ----------

# MAGIC %md
# MAGIC databricks_create_athena_external_tables.py

# COMMAND ----------

import time
import re
from collections import OrderedDict
import boto3

path = 's3://5a-datalake/temp/'
database = 'ebdb'

drop_query_template = "DROP TABLE IF EXISTS {database}.{table_name};"
create_query_template = """CREATE EXTERNAL TABLE IF NOT EXISTS
{database}.{table_name} (
  {columns})
ROW FORMAT  serde 'org.apache.hive.hcatalog.data.JsonSerDe'
LOCATION '{path}{database}/{table_name}';"""

query_output = 's3://5a-datalake/temp/databricks_output/'

def get_athena_client():
  return boto3.client('athena', 'us-east-1')

def start_athena_query(client, query, database, s3_output):
  response = client.start_query_execution(
    QueryString=query,
    QueryExecutionContext={
      'Database': database
      },
    ResultConfiguration={
      'OutputLocation': s3_output,
      }
    )
  return response

def execute_athena_query(client, query, database, s3_output):
  execution = start_athena_query(client, query, database, s3_output)
  execution_id = execution['QueryExecutionId']
  state = 'RUNNING'
  while (state in ['RUNNING']):
    response = client.get_query_execution(QueryExecutionId = execution_id)
    if 'QueryExecution' in response and \
        'Status' in response['QueryExecution'] and \
        'State' in response['QueryExecution']['Status']:
      state = response['QueryExecution']['Status']['State']
      if state == 'FAILED':
        return False
      elif state == 'SUCCEEDED':
        s3_path = response['QueryExecution']['ResultConfiguration']['OutputLocation']
        filename = re.findall('.*\/(.*)', s3_path)[0]
        return filename
    time.sleep(1)
  
  return False

def get_databricks_table_names(database):
  return spark.sql('show tables in ' + database)\
          .select("tableName")\
          .rdd.flatMap(lambda x: x)\
          .collect()


def get_table_schema(database, table_name):
  return OrderedDict(spark.sql('describe {}.{}'.format(database, table_name))\
                .select('col_name', 'data_type')\
                .collect())


def query_builder(database, table_name, schema, s3_path):
  drop_query = drop_query_template.format(\
          database=database,\
          table_name=table_name)
  
  create_query = create_query_template.format(\
            database=database,\
            table_name=table_name,\
            columns=',\n  '.join([column + ' ' + schema[column].upper() for column in schema.keys()]),\
            path=s3_path)
  
  return drop_query, create_query

  
def timestamp_to_string(data_type):
    if data_type.lower() == 'timestamp':
      return 'string'
    else:
      return data_type


def create_external_table(db, table_name, s3_path, client):
  schema = get_table_schema(database, table_name)
  schema = OrderedDict([(k, timestamp_to_string(v)) for k,v in schema.items()])
  
  drop_query, create_query = query_builder(db, table_name, schema, s3_path)

  response = execute_athena_query(client, drop_query, database, 's3://5a-datalake/temp/databricks_output/')
  if response != False:
    print('  DROP TABLE OK ' + query_output + response)
  else:
    print('  DROP FAILED')
  
  response = execute_athena_query(client, create_query, database, 's3://5a-datalake/temp/databricks_output/')
  if response != False:
    print('  CREATE TABLE OK ' + query_output + response)
  else:
    print('  CREATE TABLE FAILED')


def main():
  db = database
  s3_path = path
  client = get_athena_client()

  execute_athena_query(client, 'CREATE DATABASE IF NOT EXISTS ebdb', database, 's3://5a-datalake/temp/databricks_output/')
  
  for table_name in get_databricks_table_names(database):
    print(table_name)
    create_external_table(db, table_name, s3_path, client)
  print('\n')

if __name__ == '__main__':
    main()
