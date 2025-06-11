from datetime import datetime
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from pendulum import timezone
import os
from bietlejuice.base.opsgenie.opsgenie_callback import OpsgenieCallback

from airflow.utils.helpers import chain
from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.services.configuration_service import ConfigurationService

ENV = os.environ.get("ENVIRONMENT")
SOURCE = "tracksale"
DAG_NAME = f"reverse_{SOURCE}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
MAIN_START_DATE = datetime(2022, 2, 8, 0, 0, 0, tzinfo=timezone("America/Sao_Paulo"))

opsgenie_callback = OpsgenieCallback()
config_service = ConfigurationService(DAG_NAME)

artifacts_bucket = config_service.get_config("artifacts_bucket")
datalake_bucket = config_service.get_config("datalake_bucket_reverse")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)

BASE_SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
REVERSE_SPARK_JOB_PATH = (
    f"{databricks_bietlejuice_repo_path}/spark_jobs/reverse_{SOURCE}/"
)


CLUSTER_DESCRIPTION = config_service.get_config("databricks_12_2_med_2xlarge_general_cluster")


CLUSTER_DESCRIPTION["data_security_mode"] = "SINGLE_USER"
CLUSTER_DESCRIPTION["single_user_name"] = "{{ var.value.databricks_single_user_name }}"
CLUSTER_DESCRIPTION["spark_conf"]["spark.databricks.sql.initial.catalog.namespace"] = "quintoandar_{{ var.value.environment }}"
custom_libraries = [
    {
        "whl": f"{artifacts_bucket}/tracksale-api-client-python/"
        f"quintoandar_tracksale_api_client-0.3.1-py2.py3-none-any.whl"
    }
]

default_libraries = config_service.get_config("default_libraries")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]


dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
        "on_failure_callback": opsgenie_callback.task_failure_alert,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=None,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(databricks_conn_id="databricks_new", dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=custom_libraries + default_libraries,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(databricks_conn_id="databricks_new", dag=dag, task_id="terminate-cluster"
)

campaigns = config_service.get_config("campaigns")

for campaign in campaigns:
    campaign_code = campaign["campaign_code"]
    campaign_query = campaign["query"]
    tags = campaign["tags"]
    trigger_at_hour = campaign["trigger_at_hour"]
    trigger_at_minute = campaign["trigger_at_minute"]

    table_name = campaign_query
    slugged_table_name = table_name.replace("_", "-")

    load_campaing_targets_into_datalake = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id=f"load-{slugged_table_name}-in-datalake",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": REVERSE_SPARK_JOB_PATH
                + "load_incremental_data_into_datalake_reverse.py",
                "parameters": [ENV, datalake_bucket, SOURCE, table_name, "{{ data_interval_start | ds}}"],
            }
        },
    )

    load_targets_into_tracksale = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id=f"load-{slugged_table_name}-into-tracksale",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": REVERSE_SPARK_JOB_PATH
                + "load_targets_into_tracksale.py",
                "parameters": [
                    ENV,
                    datalake_bucket,
                    SOURCE,
                    campaign_code,
                    table_name,
                    tags,
                    trigger_at_hour,
                    trigger_at_minute,
                    "{{ data_interval_start | ds}}",
                ],
            }
        },
    )

    chain(
        create_cluster_task,
        load_campaing_targets_into_datalake,
        load_targets_into_tracksale,
        terminate_cluster_task,
    )
