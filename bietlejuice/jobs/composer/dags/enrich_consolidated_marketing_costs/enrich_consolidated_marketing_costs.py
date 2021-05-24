from datetime import datetime
import pendulum

from airflow.utils.helpers import chain
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.dags.base.datalake_sub_dag import DatalakeSubDAG
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.services import FileService

SOURCE = "consolidated_marketing_costs"
DAG_NAME = f"enrich_{SOURCE}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = Variable.get("environment")

DATALAKE_BUCKET = Variable.get("datalake_bucket")
S3_MARKETING_PATH = Variable.get("datalake_marketing_bucket")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/enrich_{SOURCE}/"
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_default_bucket")

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)
CLUSTER_DESCRIPTION = Variable.get(
    "databricks_bietlejuice_marketing_costs_cluster", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH
CUSTOM_LIBRARIES = [
    {"jar": f"{ARTIFACTS_S3_BUCKET}/jars/RedshiftJDBC42-no-awssdk-1.2.12.1017.jar"}
]
local_tz = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2019, 5, 31, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = None

EXECUTION_TIMEOUT_HOURS = 3

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=DOC_MD_BASE_URL, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=CUSTOM_LIBRARIES,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

sql_file_list = FileService.list_sql_files_without_extension_from_layer(
    SOURCE, LayerEnum.ENRICH.value
)

enrich_sub_dag = DatalakeSubDAG(
    dag_id=DAG_ID,
    env=ENV,
    datalake_bucket=DATALAKE_BUCKET,
    layer=LayerEnum.ENRICH,
    database_base_name=SOURCE,
    target_database_base_name=SOURCE,
    relative_query_path=SOURCE,
    spark_job_paths=BASE_SPARK_JOBS_PATH,
    athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
    start_date=MAIN_START_DATE,
    execution_timeout_hours=EXECUTION_TIMEOUT_HOURS,
)

enrich_sub_dags = enrich_sub_dag.build_subdags_from_sql_files(
    dag, sql_file_list, is_incremental=True, partitions=["id_date"]
)

consolidated_media_costs = enrich_sub_dags.pop("consolidated_media_costs")

consolidated_sharing_rules = QuintoAndarDatabricksSubmitRunOperator(
    task_id=f"load-mkt-consolidated-sharing-rules-to-enrich",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": f"{SPARK_JOBS_PATH}load_sharing_rules_to_datalake.py",
            "parameters": [ENV, DATALAKE_BUCKET],
        }
    },
)

enrich_table_name = "sharing_rules_marketing_daily_costs"
slugged_enrich_table_name = enrich_table_name.replace("_", "-")

sync_metastore_table_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id=f"sync-hive-metastore-{slugged_enrich_table_name}",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": f"{BASE_SPARK_JOBS_PATH}sync_metastore_tables.py",
            "parameters": [
                DATALAKE_BUCKET,
                LayerEnum.ENRICH.value,
                SOURCE,
                "--table-name",
                enrich_table_name,
            ],
        }
    },
)

validate_sync_metastore_table_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"validate-sync-hive-metastore-{slugged_enrich_table_name}",
    json={
        "spark_python_task": {
            "python_file": f"{BASE_SPARK_JOBS_PATH}validate_sync_metastore_tables.py",
            "parameters": [
                LayerEnum.ENRICH.value,
                SOURCE,
                "--table-name",
                enrich_table_name,
            ],
        }
    },
)

chain(
    consolidated_sharing_rules,
    sync_metastore_table_task,
    validate_sync_metastore_table_task,
    terminate_cluster_task,
)

base_enrich_tasks = list(enrich_sub_dags.values())
base_enrich_tasks.append(consolidated_sharing_rules)

create_cluster_task >> base_enrich_tasks >> consolidated_media_costs >> terminate_cluster_task
