from datetime import datetime
import pendulum
import os

from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import chain

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.base.airflow.helpers import TaskFlowHelper
from bietlejuice.jobs.composer.dags.base.dw_task_group import DWTaskGroup
from bietlejuice.jobs.composer.base.pipeline.layer_enum import LayerEnum


LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 7, 20, 0, 0, 0, tzinfo=LOCAL_TZ)

DW_SCHEMA = "quintoandar"
CONTEXT = "smart_price"
DAG_NAME = f"dw_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = os.environ.get("ENVIRONMENT")
SPECTRUM_IAM_ROLE = Variable.get("spectrum_iam_role")
DW_BUCKET = Variable.get("dw_bucket")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base"

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)

CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH


dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=None,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=DOC_MD_BASE_URL, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag, task_id="create-cluster", cluster_configuration=CLUSTER_DESCRIPTION
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

dw_task_group = DWTaskGroup(
    dag=dag,
    env=ENV,
    dw_bucket=DW_BUCKET,
    dw_schema=DW_SCHEMA,
    relative_query_path=DAG_NAME,
    spark_jobs_path=SPARK_JOBS_PATH,
)


dw_staging_task_group = dw_task_group.build_task_group_from_sql_files(
    layer=LayerEnum.DW_STAGING
)

dw_task_group = dw_task_group.build_task_group_from_sql_files(
    layer=LayerEnum.DW, spectrum_iam_role=SPECTRUM_IAM_ROLE
)

chain(create_cluster_task, DWTaskGroup.all_first_tasks(dw_staging_task_group))
TaskFlowHelper.chain_task_groups_via_common_table(dw_staging_task_group, dw_task_group)
chain(DWTaskGroup.all_last_tasks(dw_task_group), terminate_cluster_task)
