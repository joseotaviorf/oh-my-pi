from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG

DAG_ID = "docx"
ENV = Variable.get("environment")

S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")

LOAD_DOCX_INTO_DATALAKE_RAW_FILE_PATH = (
    S3_PREFIX + "/spark_jobs/{}/{}/load_docx_into_datalake.py".format(ENV, DAG_ID)
)
CREATE_RAW_EXTERNAL_TABLES_FILE_PATH = (
    S3_PREFIX + "/spark_jobs/{}/{}/create_raw_external_tables.py".format(ENV, DAG_ID)
)

LOGS_OUTPUT_PATH = "s3://5a-databricks/logs/jobs/{}".format(DAG_ID)

CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

DEFAULT_LIBRARIES = Variable.get("bietlejuice_default_libraries", deserialize_json=True)
CUSTOM_LIBRARIES = [
    {"jar": "s3://5a-artifacts/mysql-connector-java/mysql-connector-java-5.1.47.jar"}
]
LIBRARIES_DESCRIPTION = DEFAULT_LIBRARIES + CUSTOM_LIBRARIES

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=datetime(2019, 5, 31, 0, 0, 0),
    schedule_interval="0 4 * * *",
    max_active_runs=1,
    catchup=False,
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

docx_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="docx-to-datalake-raw",
    dag=dag,
    json={"spark_python_task": {"python_file": LOAD_DOCX_INTO_DATALAKE_RAW_FILE_PATH}},
)

create_raw_external_tables_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="create-raw-external-tables",
    dag=dag,
    json={"spark_python_task": {"python_file": CREATE_RAW_EXTERNAL_TABLES_FILE_PATH}},
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

airflow_helpers.chain(
    create_cluster_task,
    docx_to_datalake_raw_task,
    create_raw_external_tables_task,
    terminate_cluster_task,
)
