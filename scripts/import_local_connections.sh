#!/bin/bash

cat airflow_python3/local_connection.json | jq -c '.envs[]' | while read row;
do
  conn_id=$(echo ${row} | jq -r ${1} '.conn_id')
  conn_type=$(echo ${row} | jq -r ${1} '.conn_type')
  conn_host=$(echo ${row} | jq -r ${1} '.host')
  conn_login=$(echo ${row} | jq -r ${1} '.login')
  conn_password=$(echo ${row} | jq -r ${1} '.password')
  conn_extra=$(echo ${row} | jq -c ${1} '.extra[]')

  airflow connections -d --conn_id $conn_id
  airflow connections -a --conn_id $conn_id --conn_type $conn_type --conn_host $conn_host --conn_login $conn_login --conn_password $conn_password --conn_extra ${conn_extra/\{DATABRICKS_TOKEN\}/$DATABRICKS_TOKEN}
done