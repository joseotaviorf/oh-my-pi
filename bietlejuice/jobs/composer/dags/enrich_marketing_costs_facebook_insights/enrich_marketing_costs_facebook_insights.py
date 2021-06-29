from datetime import datetime
import json
import os
import pendulum

from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)
import airflow.utils.helpers as airflow_helpers

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.services import FileService


def sync_metastore(table_name, table_task):

    slugged_table_name = table_name.replace("_", "-")

    sync_metastore_table_task = QuintoAndarDatabricksSubmitRunOperator(
        task_id=f"sync-{slugged_table_name}-hive-metastore",
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": BASE_SPARK_JOBS_PATH + "sync_metastore_tables.py",
                "parameters": [
                    DATALAKE_BUCKET,
                    LayerEnum.ENRICH.value,
                    TARGET,
                    "--table-name",
                    table_name,
                ],
            }
        },
    )

    validate_sync_metastore_table_task = QuintoAndarDatabricksSubmitRunOperator(
        dag=dag,
        task_id=f"validate-sync-{slugged_table_name}-hive-metastore",
        json={
            "spark_python_task": {
                "python_file": BASE_SPARK_JOBS_PATH
                + "validate_sync_metastore_tables.py",
                "parameters": [
                    LayerEnum.ENRICH.value,
                    TARGET,
                    "--table-name",
                    table_name,
                ],
            }
        },
    )

    airflow_helpers.chain(
        table_task,
        sync_metastore_table_task,
        validate_sync_metastore_table_task,
        terminate_cluster_task,
    )


PARTITION_COLS = ["year", "month", "day"]
TARGET = "marketing_costs"
MEDIA = "facebook_insights"
DAG_NAME = f"enrich_{TARGET}_{MEDIA}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = os.environ.get("ENVIRONMENT")
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

DATALAKE_BUCKET = Variable.get("datalake_bucket")
S3_MARKETING_PATH = Variable.get("datalake_marketing_bucket")
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"
SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/enrich_{TARGET}_{MEDIA}/"
ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

local_tz = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2019, 5, 31, 0, 0, 0, tzinfo=local_tz)

CONFIGS_YAML_PATH = os.path.join(
    os.path.dirname(os.path.realpath(__file__)),
    "enrich_marketing_costs_facebook_insights_config.yaml",
)

CONFIGS = FileService.get_dict_from_yaml_file(CONFIGS_YAML_PATH)

ACCOUNTS_NAME_MAPPING = CONFIGS["account_names"]
BREAKDOWNS_SOCIAL = CONFIGS["breakdowns"]["social"]
BREAKDOWNS_GENERAL = CONFIGS["breakdowns"]["general"]
str_partitions = json.dumps(PARTITION_COLS)
str_breakdowns_social = json.dumps(BREAKDOWNS_SOCIAL)
str_breakdowns_general = json.dumps(BREAKDOWNS_GENERAL)
str_accounts_name_mapping = json.dumps(ACCOUNTS_NAME_MAPPING)

(
    database_name,
    database_location,
    athena_database_name,
) = DatalakeMetastoreService.get_layer_info(
    ENV, TARGET, DATALAKE_BUCKET, LayerEnum.ENRICH.value
)

EXECUTION_TIMEOUT_HOURS = 3


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

load_facebook_social_table = QuintoAndarDatabricksSubmitRunOperator(
    task_id="load-facebook-social-insights-to-enrich",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": f"{SPARK_JOBS_PATH}load_facebook_insights.py",
            "parameters": [
                ENV,
                DATALAKE_BUCKET,
                TARGET,
                TARGET,
                "facebook_social_insights",
                str_breakdowns_social,
                str_partitions,
                str_accounts_name_mapping,
                "{{ ds }}",
            ],
        }
    },
)

sync_metastore("facebook_social_insights", load_facebook_social_table)

load_facebook_table = QuintoAndarDatabricksSubmitRunOperator(
    task_id="load-facebook-insights-to-enrich",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": f"{SPARK_JOBS_PATH}load_facebook_insights.py",
            "parameters": [
                ENV,
                DATALAKE_BUCKET,
                TARGET,
                TARGET,
                "facebook_insights",
                str_breakdowns_general,
                str_partitions,
                str_accounts_name_mapping,
                "{{ ds }}",
            ],
        }
    },
)

sync_metastore("facebook_insights", load_facebook_table)

create_cluster_task >> [
    load_facebook_social_table,
    load_facebook_table,
] >> terminate_cluster_task
