#!/bin/bash
export > /export

cd /bi-etl-ejuice/local

airflow initdb >&2

cat $AIRFLOW_HOME/connections.json | jq -c '.envs[]' | while read row;
do
  conn_id=$(echo ${row} | jq -r ${2} '.conn_id')
  conn_type=$(echo ${row} | jq -r ${2} '.conn_type')
  conn_host=$(echo ${row} | jq -r ${2} '.host')
  conn_login=$(echo ${row} | jq -r ${2} '.login')
  conn_password=$(echo ${row} | jq -r ${2} '.password')
  conn_extra=$(echo ${row} | jq -c ${2} '.extra[]')

  airflow connections delete $conn_id
  airflow connections add $conn_id \
    --conn-type $conn_type \
    --conn-host $conn_host \
    --conn-login $conn_login \
    --conn-password $conn_password \
    --conn-extra ${conn_extra/\{DATABRICKS_TOKEN\}/$1}
done

airflow variables -i $AIRFLOW_HOME/variables.json
airflow scheduler >&2 &
airflow webserver >&2
