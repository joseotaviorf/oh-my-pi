from datetime import datetime
import os
import pendulum

from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.services import FileService

from bietlejuice.jobs.composer.dags.enrich_marketing_costs_facebook_insights.facebook_sub_dag import (
    FacebookSubDAG,
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
CLUSTER_DESCRIPTION = Variable.get(
    "databricks_bietlejuice_marketing_costs_cluster", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH
LIBRARIES_DESCRIPTION = Variable.get(
    "bietlejuice_default_libraries", deserialize_json=True
)

local_tz = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2019, 5, 31, 0, 0, 0, tzinfo=local_tz)

CONFIGS_YAML_PATH = os.path.join(
    os.path.dirname(os.path.realpath(__file__)),
    "enrich_marketing_costs_facebook_insights_config.yaml",
)

CONFIGS = FileService.get_dict_from_yaml_file(CONFIGS_YAML_PATH)

ACCOUNTS_NAME_MAPPING = CONFIGS["account_names"]

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
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

facebook_sub_dag_class = FacebookSubDAG(
    dag_id=DAG_ID,
    env=ENV,
    datalake_bucket=DATALAKE_BUCKET,
    database_base_name=TARGET,
    target_database_base_name=TARGET,
    spark_job_paths=SPARK_JOBS_PATH,
    athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
    start_date=MAIN_START_DATE,
)

facebook_sub_dag = facebook_sub_dag_class.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="load-facebook-insights-to-enrich",
    sub_dag_func=facebook_sub_dag_class.build_subdag,
    table_name="facebook_insights",
    slugged_table_name="facebook-insights",
    accounts_name_mapping=ACCOUNTS_NAME_MAPPING,
    partitions=PARTITION_COLS,
    breakdowns=CONFIGS["breakdowns"]["general"],
)

facebook_social_sub_dag = facebook_sub_dag_class.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="load-facebook-social-insights-to-enrich",
    sub_dag_func=facebook_sub_dag_class.build_subdag,
    table_name="facebook_social_insights",
    slugged_table_name="facebook-social-insights",
    accounts_name_mapping=ACCOUNTS_NAME_MAPPING,
    partitions=PARTITION_COLS,
    breakdowns=CONFIGS["breakdowns"]["social"],
)

create_cluster_task >> [
    facebook_sub_dag,
    facebook_social_sub_dag,
] >> terminate_cluster_task
