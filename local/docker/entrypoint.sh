#!/bin/bash
export > /export

cd /bi-etl-ejuice/local

airflow initdb >&2

cat $AIRFLOW_HOME/connections.json | jq -c '.envs[]' | while read row;
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

airflow variables -i $AIRFLOW_HOME/variables.json
airflow scheduler >&2 &
airflow webserver >&2
