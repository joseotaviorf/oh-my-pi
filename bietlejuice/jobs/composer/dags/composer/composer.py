from datetime import datetime

from airflow.models import DAG, Variable
from airflow.operators.quintoandar_mysql_to_s3 import QuintoAndarMySqlToS3Operator

from bietlejuice.jobs.composer.base.airflow import BaseDAG

DAG_ID = "bietlejuice.composer"
ENV = Variable.get("environment")

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=datetime(2019, 8, 1, 0, 0, 0),
    schedule_interval="0 4 * * *",
    max_active_runs=1,
    catchup=False,
)

dump_dag_table_task = QuintoAndarMySqlToS3Operator(
    dag=dag,
    table='dag',
    task_id="dump_dag_table_task",
    bucket='5a-datalake-{}'.format(ENV),
    filename='data.json',
    s3_file_path='raw/test_operator/dag',
    mysql_conn_id='airflow_db',
    gzip=True
)

dump_dag_run_table_task = QuintoAndarMySqlToS3Operator(
    dag=dag,
    table='dag_run',
    task_id="dump_dag_run_table_task",
    bucket='5a-datalake-{}'.format(ENV),
    filename='data.json',
    s3_file_path='raw/test_operator/dag_run',
    mysql_conn_id='airflow_db',
    gzip=True
)

dump_task_fail_table_task = QuintoAndarMySqlToS3Operator(
    dag=dag,
    sql='task_fail',
    task_id="dump_task_fail_table_task",
    bucket='5a-datalake-{}'.format(ENV),
    filename='data.json',
    s3_file_path='raw/test_operator/task_fail',
    mysql_conn_id='airflow_db',
    gzip=True
)

# mysql_table_to_raw = QuintoAndarMySqlToS3Operator(
#     dag=dag,
#     table='simulation',
#     task_id="mysql_table_to_raw",
#     bucket='5a-datalake-forno',
#     filename='data.json',
#     s3_file_path='raw/test_operator/simulation',
#     mysql_conn_id='docx',
#     export_format='json',
#     gzip=True
# )
#
# create_raw_table = QuintoAndarCreateAthenaExternalTableOperator(
#     dag=dag,
#     task_id='create_raw_table',
#     database='datalake_test',
#     table='simulation',
#     ddl_query=BaseETL.get_query_from_file_name('{}/ddl/raw/composer/test_operator.ddl'.format(DATALAKE_SQL_DIR)),
#     output_location="s3://5a-datalake-forno/query_results/"
# )
#
# mysql_table_to_raw >> create_raw_table
