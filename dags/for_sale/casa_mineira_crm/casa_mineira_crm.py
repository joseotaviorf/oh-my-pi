from datetime import datetime

import json
import pendulum
import os

from airflow.models import DAG, Variable
from airflow.utils.helpers import chain, cross_downstream
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

ENV = os.environ.get("ENVIRONMENT")
SOURCE = "casa_mineira_crm"
CONTEXT = SOURCE

config_service = ConfigurationService(dag_name=SOURCE)
default_libraries = config_service.get_config("default_libraries")

DAG_ID = f"bietlejuice.{SOURCE}"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 11, 1, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 2 * * *"

ATHENA_QUERY_RESULT_LOCATION = config_service.get_config("athena_query_results_bucket")
S3_PREFIX = config_service.get_config("databricks_bietlejuice_repo_path")
DATALAKE_BUCKET = config_service.get_config("datalake_bucket")
DOC_MD_BASE_URL = config_service.get_config("doc_md_chart_url")

BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"
RAW_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{SOURCE}"
RAW_SPARK_JOB_PATH = (
    f"{S3_PREFIX}/spark_jobs/{CONTEXT}/load_{CONTEXT}_into_datalake_raw.py"
)

CLUSTER_DESCRIPTION = Variable.get(
    f"databricks_9_1_med_general_cluster", deserialize_json=True
)
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FOR_SALE,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(SOURCE).format(chart_url=DOC_MD_BASE_URL, dag_id=DAG_ID),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=default_libraries,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=DATALAKE_BUCKET,
    relative_query_path=CONTEXT,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
    athena_query_result_location=ATHENA_QUERY_RESULT_LOCATION,
)

source_root_path = config_service.get_config("source_root_path")
source_path_template = config_service.get_config("source_path_template")
job_extra_args = config_service.get_config("job_extra_args")

parameters = [
    CONTEXT,
    source_root_path,
    source_path_template,
    json.dumps(job_extra_args),
]

raw_task_groups = task_group.build_raw_task_group_for_all_tables(
    source=SOURCE,
    target_database_base_name=CONTEXT,
    extraction_spark_job_file=RAW_SPARK_JOB_PATH,
    raw_spark_job_extra_args=parameters,
)


clean_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.CLEAN,
    source_database_base_name=CONTEXT,
    target_database_base_name=CONTEXT,
)


chain(create_cluster_task, DatalakeTaskGroup.first_tasks(raw_task_groups))

cross_downstream(
    DatalakeTaskGroup.last_tasks(raw_task_groups),
    DatalakeTaskGroup.all_first_tasks(clean_task_groups),
)

terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(clean_task_groups))
