from datetime import datetime
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from pendulum import timezone
import os

from airflow.utils.helpers import chain
from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.airflow.task_groups.reverse_task_group import ReverseTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.base.opsgenie.opsgenie_callback import OpsgenieCallback

# ENV setup
ENV = os.environ.get("ENVIRONMENT")

# DAG and Jobs params setup
SOURCE = "nexxera"
DAG_NAME = f"reverse_{SOURCE}"
DAG_ID = f"bietlejuice.{DAG_NAME}"

MAIN_START_DATE = datetime(2022, 7, 12, 0, 0, 0, tzinfo=timezone("America/Sao_Paulo"))

config_service = ConfigurationService(DAG_NAME)

# S3 path setup
datalake_bucket = config_service.get_config("datalake_bucket")
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
base_spark_jobs_path = f"{s3_prefix}/spark_jobs/base/"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

reverse_spark_job_path = (
    f"{s3_prefix}/spark_jobs/{DAG_NAME}/load_s3_data_into_external_bucket.py"
)

cluster_description = config_service.get_config("databricks_12_2_med_general_cluster")


cluster_description["data_security_mode"] = "SINGLE_USER"
cluster_description["single_user_name"] = "{{ var.value.databricks_single_user_name }}"
cluster_description["spark_conf"]["spark.databricks.sql.initial.catalog.namespace"] = "quintoandar_{{ var.value.environment }}"
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

default_libraries = config_service.get_config("default_libraries")
external_s3_bucket = config_service.get_config("external_s3_bucket")
partition_cols = config_service.get_config("partition_cols")

opsgenie_callback = OpsgenieCallback()
dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FINTECH,
        "wait_for_downstream": False,
        "depends_on_past": False,
        "on_failure_callback": opsgenie_callback.task_failure_alert,

    },
    start_date=MAIN_START_DATE,
    schedule_interval=None,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID, ENV=ENV
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(databricks_conn_id="databricks_new", dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_description,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=default_libraries,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(databricks_conn_id="databricks_new", dag=dag, task_id="terminate-cluster"
)


task_group = ReverseTaskGroup(databricks_conn_id="databricks_new", dag=dag,
    env=ENV,
    s3_bucket=datalake_bucket,
    relative_query_path=DAG_NAME,
    spark_jobs_path=base_spark_jobs_path,
)

datalake_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.REVERSE,
    source_database_base_name=SOURCE,
    target_database_base_name=SOURCE,
    is_incremental=True,
    partitions=partition_cols,
)


external_bucket_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id=f"load_s3_data_into_external_bucket",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": reverse_spark_job_path,
            "parameters": [ENV,
                        datalake_bucket,
                        SOURCE,
                        external_s3_bucket,
                        "{{ ds }}"
                        ],
        }
    },
)


chain(create_cluster_task, ReverseTaskGroup.all_first_tasks(datalake_task_groups))
chain(ReverseTaskGroup.all_last_tasks(datalake_task_groups), external_bucket_task)
chain(external_bucket_task, terminate_cluster_task)
