#!/bin/bash
export > /export

cd /bi-etl-ejuice

airflow initdb >&2

airflow variables -i /bi-etl-ejuice/airflow_python3/local_env.json
airflow scheduler >&2 &
airflow webserver >&2
