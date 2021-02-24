from datetime import datetime
import pendulum

from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.dags.base.dw_staging_sub_dag import DWStagingSubDAG
from bietlejuice.jobs.composer.dags.base.dw_sub_dag import DWSubDAG
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.base.pipeline.layer_enum import LayerEnum


LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 7, 20, 0, 0, 0, tzinfo=LOCAL_TZ)

DW_SCHEMA = "quintoandar"
CONTEXT = "smart_price"
DAG_NAME = f"dw_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = Variable.get("environment")
SPECTRUM_IAM_ROLE = Variable.get("spectrum_iam_role")
DW_BUCKET = Variable.get("dw_bucket")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base"

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)

CLUSTER_DESCRIPTION = Variable.get(
    "databricks_bietlejuice_dw_smart_price ", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)

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
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

dw_staging_sub_dag = DWStagingSubDAG(
    dag_id=DAG_ID,
    start_date=MAIN_START_DATE,
    env=ENV,
    dw_bucket=DW_BUCKET,
    dw_schema=DW_SCHEMA,
    relative_query_path=DAG_NAME,
    spark_job_path=SPARK_JOBS_PATH,
)

dw_sub_dag = DWSubDAG(
    dag_id=DAG_ID,
    start_date=MAIN_START_DATE,
    env=ENV,
    dw_bucket=DW_BUCKET,
    dw_schema=DW_SCHEMA,
    relative_query_path=DAG_NAME,
    spark_job_path=SPARK_JOBS_PATH,
    spectrum_iam_role=SPECTRUM_IAM_ROLE,
)

file_list = FileService.list_sql_files_without_extension_from_layer(
    DAG_NAME, LayerEnum.DW.value
)

dw_staging_sub_dags = dw_staging_sub_dag.build_subdags_from_sql_files(dag, file_list)

dw_sub_dags = dw_sub_dag.build_subdags_from_sql_files(dag, file_list)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

BaseDAG.set_dependencies_in_sequence(file_list, dw_staging_sub_dags, dw_sub_dags)

create_cluster_task >> list(dw_staging_sub_dags.values())
list(dw_sub_dags.values()) >> terminate_cluster_task
