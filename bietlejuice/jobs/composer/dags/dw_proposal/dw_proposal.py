from datetime import datetime
import pendulum
import os

from airflow.models import DAG, Variable
from airflow.utils.helpers import chain, cross_downstream
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.dags.base.dw_task_group import DWTaskGroup
from bietlejuice.jobs.composer.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 2, 20, 0, 0, 0, tzinfo=LOCAL_TZ)

DW_SCHEMA = "public"
CONTEXT = "proposal"
DAG_NAME = f"dw_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = os.environ.get("ENVIRONMENT")

config_service = ConfigurationService(DAG_NAME)
spectrum_iam_role = config_service.get_config("spectrum_iam_role")
dw_bucket = config_service.get_config("dw_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base"

CLUSTER_DESCRIPTION = Variable.get(
    "databricks_9_1_min_general_cluster", deserialize_json=True
)

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FOR_RENT,
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
    dag=dag, task_id="create-cluster", cluster_configuration=CLUSTER_DESCRIPTION
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

tables = config_service.get_config("tables")
for table_name, table_config in tables.items():
    dw_schema = table_config["dw_schema"]

    task_group = DWTaskGroup(
        dag=dag,
        env=ENV,
        dw_bucket=dw_bucket,
        dw_schema=dw_schema,
        relative_query_path=DAG_NAME,
        spark_jobs_path=spark_jobs_path,
    )

    dw_staging_task_group = task_group.build_dw_staging_task_group(
        table_name=table_name
    )

    dw_task_group = task_group.build_dw_task_group(
        table_name=table_name, spectrum_iam_role=spectrum_iam_role
    )

    chain(create_cluster_task, DWTaskGroup.first_tasks(dw_staging_task_group))
    cross_downstream(
        DWTaskGroup.last_tasks(dw_staging_task_group),
        DWTaskGroup.first_tasks(dw_task_group),
    )
    chain(DWTaskGroup.last_tasks(dw_task_group), terminate_cluster_task)
