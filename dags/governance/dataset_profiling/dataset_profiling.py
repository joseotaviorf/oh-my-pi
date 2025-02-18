import os

from airflow.utils.helpers import chain
from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from pendulum import datetime, timezone

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.opsgenie.opsgenie_callback import OpsgenieCallback

# ENV setup
ENV = os.environ.get("ENVIRONMENT")

# DAG and Jobs params setup
SOURCE = "dataset_profiling"
DAG_NAME = f"{SOURCE}"
DAG_ID = f"bietlejuice.{DAG_NAME}"

MAIN_START_DATE = datetime(2023, 6, 15, 0, 0, 0, tzinfo=timezone("America/Sao_Paulo"))

config_service = ConfigurationService(DAG_NAME)

# S3 path setup
datalake_bucket = config_service.get_config("datalake_bucket")
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
base_spark_jobs_path = f"{s3_prefix}/spark_jobs/base"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
inmetro_bucket = config_service.get_config("inmetro_bucket")

profiling_spark_job_path = f"{s3_prefix}/spark_jobs/{SOURCE}/run_profiling_on_schema.py"
schemas_list = config_service.get_config("schemas_list")

CLUSTER_DESCRIPTION = config_service.get_config("databricks_13_3_med_general_cluster")

CLUSTER_DESCRIPTION["data_security_mode"] = "SINGLE_USER"
CLUSTER_DESCRIPTION["single_user_name"] = "{{ var.value.databricks_single_user_name }}"
CLUSTER_DESCRIPTION["spark_conf"]["spark.databricks.sql.initial.catalog.namespace"] = "quintoandar_{{ var.value.environment }}"
default_libraries = config_service.get_config("default_libraries")

if not schemas_list:
    raise ValueError(
        "No schemas were found to be profiled. Please add at least one schema "
        f"into 'schemas_list' parameter of '{ENV}_conf' file."
    )

opsgenie_callback = OpsgenieCallback()
dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_GOVERNANCE,
        "wait_for_downstream": False,
        "depends_on_past": False,
        "on_failure_callback": opsgenie_callback.task_failure_alert,
    },
    start_date=MAIN_START_DATE,
    schedule_interval="0 10 * * 0",
    doc_md=BaseDAG.get_dag_doc(DAG_NAME),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(databricks_conn_id="databricks_new", dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=default_libraries,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(databricks_conn_id="databricks_new", dag=dag, task_id="terminate-cluster"
)


run_data_profiling_tasks = []
for schema in schemas_list:
    run_data_profiling_tasks.append(
        QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id=f"run-data-profiling-{schema}",
            dag=dag,
            json={
                "spark_python_task": {
                    "python_file": profiling_spark_job_path,
                    "parameters": [ENV, "{{ ds }}", inmetro_bucket, schema],
                }
            },
        )
    )

chain(create_cluster_task, run_data_profiling_tasks)
chain(run_data_profiling_tasks, terminate_cluster_task)
