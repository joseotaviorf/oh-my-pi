export > /export

airflow initdb >&2
# python3 setup.py develop 2>&1 | tee -a /setup.log
airflow scheduler >&2 &
airflow webserver >&2
