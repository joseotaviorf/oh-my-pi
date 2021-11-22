import os
from datetime import datetime
from pendulum import timezone

from airflow.utils.helpers import chain
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)
from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.jobs.composer.base.pipeline.layer_enum import LayerEnum
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

# ENV setup
ENV = os.environ.get("ENVIRONMENT")

# DAG params setup
SOURCE = 'lost_listings'
CONTEXT = 'marketing_segmentations'
DAG_NAME = f"enrich_{SOURCE}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
MAIN_START_DATE = datetime(2021, 11, 1, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "0 10 * * *"

config_service = ConfigurationService(DAG_NAME)
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
spark_jobs_logs_path = config_service.get_config("spark_jobs_logs_path")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

custom_libraries = config_service.get_config("custom_libraries")
slugged_table_name = config_service.get_config("slugged_table_name")
table_name = config_service.get_config("table_name")
partition_cols = config_service.get_config("partition_cols")

BASE_SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
ENRICH_SPARK_JOB_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/load_{SOURCE}_enrich.py"

# cluster setup
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = f"{spark_jobs_logs_path}{DAG_ID}"

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
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=custom_libraries
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

load_table_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id=f"load-{LayerEnum.ENRICH.value}-{slugged_table_name}",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": ENRICH_SPARK_JOB_PATH,
            "parameters": [
                ENV,
                datalake_bucket,
                SOURCE,
                CONTEXT,
                "{{ ds }}",
            ],
        }
    },
)

create_external_table_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"create-{LayerEnum.ENRICH.value}-{slugged_table_name}-external-table",
    json={
        "spark_python_task": {
            "python_file": f"{BASE_SPARK_JOBS_PATH}/create_external_table.py",
            "parameters": [
                ENV,
                datalake_bucket,
                athena_query_results_bucket,
                LayerEnum.ENRICH.value,
                CONTEXT,
                table_name,
                str(partition_cols),
                True,
            ],
        }
    },
)

sync_metastore_table_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"sync-hive-metastore-{LayerEnum.ENRICH.value}-{slugged_table_name}",
    json={
        "spark_python_task": {
            "python_file": f"{BASE_SPARK_JOBS_PATH}/sync_metastore_tables.py",
            "parameters": [
                datalake_bucket,
                LayerEnum.ENRICH.value,
                CONTEXT,
                "--table-name",
                table_name,
            ],
        }
    },
)

propagate_table_metadata_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"propagate-table-metadata-{LayerEnum.ENRICH.value}-{slugged_table_name}",
    json={
        "spark_python_task": {
            "python_file": f"{BASE_SPARK_JOBS_PATH}/propagate_table_metadata.py",
            "parameters": [
                LayerEnum.ENRICH.value,
                MetadataTypeEnum.LINEAGE.value,
                CONTEXT,
                table_name,
            ],
        }
    },
)

chain(
    create_cluster_task,
    load_table_task,
    sync_metastore_table_task,
    propagate_table_metadata_task,
    terminate_cluster_task
)
chain(
    load_table_task,
    create_external_table_task,
    terminate_cluster_task
)