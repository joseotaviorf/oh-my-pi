from datetime import datetime
import pendulum

from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.operators.dummy_operator import DummyOperator

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.dags.dw_marketing_costs.sub_dag.incremental_dw_sub_dag import (
    IncrementalDWSubDAG,
)
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.services import FileService

DW_SCHEMA = "marketing_costs"
TARGET = "dw_marketing_costs"
DAG_ID = f"bietlejuice.{TARGET}"

ENV = Variable.get("environment")
DW_BUCKET = Variable.get("dw_bucket")
DATALAKE_BUCKET = Variable.get("datalake_bucket")
S3_MARKETING_PATH = Variable.get("datalake_marketing_bucket")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"
MARKETING_COSTS_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/dw_marketing_costs/"
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
SPECTRUM_IAM_ROLE = Variable.get("spectrum_iam_role")

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)

CLUSTER_DESCRIPTION = Variable.get(
    "databricks_bietlejuice_dw_marketing_costs_cluster", deserialize_json=True
)

CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH
LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)

local_tz = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2019, 5, 31, 0, 0, 0, tzinfo=local_tz)

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=None,
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

media_names = FileService.list_layer_sql_files(TARGET, "")

for media_name in media_names:

    dw_staging_file_list = FileService.list_sql_files_without_extension_from_layer(
        TARGET, f"{media_name}/{LayerEnum.DW.value}"
    )

    dw_staging_sub_dag = IncrementalDWSubDAG(
        dag_id=DAG_ID,
        start_date=MAIN_START_DATE,
        env=ENV,
        dw_bucket=DW_BUCKET,
        dw_schema=DW_SCHEMA,
        relative_query_path=f"{TARGET}/{media_name}",
        spark_job_path=MARKETING_COSTS_SPARK_JOBS_PATH,
    )

    dw_staging_sub_dags = dw_staging_sub_dag.build_subdags_from_sql_files(
        dag,
        dw_staging_file_list,
        test_ods_migration=False,
        partitions=["load_date"],
        dw_query_filters={"load_date": "date('{year}-{month}-{day}')"},
        spectrum_iam_role=SPECTRUM_IAM_ROLE,
    )

join = DummyOperator(task_id="join", dag=dag, trigger_rule="none_failed")

dims_sub_dags = []
facts_sub_dags = []
for key, value in dw_staging_sub_dags.items():
    if "fact" in key:
        facts_sub_dags.append(value)
    else:
        dims_sub_dags.append(value)

create_cluster_task >> dims_sub_dags >> join >> facts_sub_dags >> terminate_cluster_task
