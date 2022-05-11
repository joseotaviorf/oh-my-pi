from airflow.utils.helpers import chain
from datetime import datetime
import pendulum
import os

from airflow.models import DAG, Variable
from airflow.operators.python_operator import ShortCircuitOperator
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.jobs.composer.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.jobs.composer.base.pipeline.layer_enum import LayerEnum
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 7, 1, 0, 0, 0, tzinfo=LOCAL_TZ)

SOURCE = "dai_report"
DAG_NAME = f"enrich_{SOURCE}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = os.environ.get("ENVIRONMENT")


config_service = ConfigurationService(DAG_NAME)
datalake_bucket = config_service.get_config("datalake_bucket")
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base"
DAI_CUSTOM_SPARK_JOB_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/{DAG_NAME}/"

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    databricks_bietlejuice_repo_path, DAG_ID
)

CLUSTER_DESCRIPTION = Variable.get(
    "databricks_9_1_min_general_cluster", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)

libraries_description = [
    *LIBRARIES_DESCRIPTION,
    config_service.get_config("cluster_extra_libs"),
]


def check_valid_run_date(dag_execution_date):
    if datetime.strptime(dag_execution_date, "%Y-%m-%d").day + 1 == 10:
        return True


dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_BEDROCK,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=None,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=libraries_description,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

skip_run_task = ShortCircuitOperator(
    task_id=f"check-day-to-skip-execution",
    python_callable=check_valid_run_date,
    op_kwargs={"dag_execution_date": "{{ds}}"},
)

datalake_task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=DAG_NAME,
    spark_jobs_path=SPARK_JOBS_PATH,
    athena_query_result_location=athena_query_results_bucket,
)

enrich_task_groups = datalake_task_group.build_task_group_from_sql_files(
    layer=LayerEnum.ENRICH,
    source_database_base_name=SOURCE,
    target_database_base_name=SOURCE,
)

query_export_xlsx = config_service.get_config("query_export_xlsx")
format_options = config_service.get_config("format_options")
out_path = config_service.get_config("out_path")
load_data_into_s3 = QuintoAndarDatabricksSubmitRunOperator(
    task_id=f"load-{SOURCE}-in-s3",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": DAI_CUSTOM_SPARK_JOB_PATH + "load_data_into_xlsx_s3.py",
            "parameters": [
                ENV,
                SOURCE,
                query_export_xlsx,
                out_path,
                format_options,
                "{{ds}}",
            ],
        }
    },
)

chain(
    skip_run_task,
    create_cluster_task,
    DatalakeTaskGroup.all_first_tasks(enrich_task_groups),
)
chain(
    DatalakeTaskGroup.all_last_tasks(enrich_task_groups),
    load_data_into_s3,
    terminate_cluster_task,
)
