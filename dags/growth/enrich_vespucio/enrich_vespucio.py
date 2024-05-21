import os
import re
from datetime import datetime

import pendulum
from airflow.models import DAG
from airflow.utils.helpers import chain
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.operators.dummy_operator import DummyOperator

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 12, 12, 0, 0, 0, tzinfo=LOCAL_TZ)

CONTEXT = "vespucio"
DAG_NAME = f"enrich_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"

config_service = ConfigurationService(DAG_NAME)

DATALAKE_BUCKET = config_service.get_config("datalake_bucket")
DATABRICKS_BIETLEJUICE_REPO_PATH = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
CUSTOM_CLUSTER = "custom_cluster"
CUSTOM_LIBRARIES = config_service.get_config("custom_libraries")
DOC_MD_CHART_URL = config_service.get_config("doc_md_chart_url")
BASE_SPARK_JOBS_PATH = f"{DATABRICKS_BIETLEJUICE_REPO_PATH}/spark_jobs/base/"

dag_custom_init_script = config_service.get_config("init_script")
dag_spark_conf = config_service.get_config("spark_conf")
cluster_configuration = config_service.get_config(CUSTOM_CLUSTER)
default_libraries = config_service.get_config("default_libraries")
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")

cluster_configuration["init_scripts"].append(dag_custom_init_script[0])
for dag_config in dag_spark_conf:
    for key, value in dag_config.items():
        cluster_configuration["spark_conf"][key] = value

reverse_spark_job_path = (
    f"{DATABRICKS_BIETLEJUICE_REPO_PATH}/spark_jobs/{DAG_NAME}/load_s3_data_into_external_bucket.py"
)

calculate_dejavu_id_job_path = (
    f"{DATABRICKS_BIETLEJUICE_REPO_PATH}/spark_jobs/{DAG_NAME}/calculate_dejavu_id.py"
)

external_s3_bucket = config_service.get_config("external_s3_bucket")
tables_to_reverse = str(config_service.get_config("tables_to_reverse"))
addresses_s2_geometry_mapping_table = config_service.get_config("addresses_s2_geometry_mapping_table")
requests_limit = config_service.get_config("requests_limit")
table_task_group_parameters = config_service.get_config("table_task_group_parameters")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

ENV = os.environ.get("ENVIRONMENT")

def get_date_param(dag_run, ds, date_param_name):
    date_param = dag_run.conf.get(date_param_name) if dag_run.conf else None
    if date_param and re.match(r"[0-9]{4}\-[0-9]{2}\-[0-9]{2}", date_param):
        return date_param
    return ds

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_GROWTH,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=None,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=DOC_MD_CHART_URL, dag_id=DAG_ID
    ),
    user_defined_macros={"get_date_param": get_date_param},
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_configuration,
    libraries=default_libraries + CUSTOM_LIBRARIES,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

datalake_task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=DATALAKE_BUCKET,
    relative_query_path=DAG_NAME,
    spark_jobs_path=BASE_SPARK_JOBS_PATH,
    athena_query_result_location=athena_query_results_bucket,
)

tables = datalake_task_group._get_table_names_from_sql_files(layer=LayerEnum.ENRICH)

enrich_task_groups = {}

for table in tables:
    enrich_task_groups[table] = datalake_task_group.build_enrich_task_group(
        source_database_base_name=CONTEXT,
        target_database_base_name=CONTEXT,
        table_name=table,
        partitions=table_task_group_parameters[table]["partition_cols"],
        is_incremental=table_task_group_parameters[table]["is_incremental"],
        has_create_external_table_task=False,
        extra_query_template_params={
            "load_start_date": "{{ get_date_param(dag_run, ds, 'load_start_date') }}",
            "load_end_date": "{{ get_date_param(dag_run, ds, 'load_end_date') }}",
        },
        # execution_date="",
        spark_session_configs={"udfs": ["GROWTH_VESPUCIO_SCORE"]},
    )

external_bucket_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id=f"load_s3_data_into_external_bucket",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": reverse_spark_job_path,
            "parameters": [
                ENV,
                DATALAKE_BUCKET,
                CONTEXT,
                external_s3_bucket,
                tables_to_reverse
            ],
        }
    },
)

calculate_dejavu_id_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id=DatalakeTaskGroup.generate_default_task_id(
        task_prefix=DatalakeTaskGroup.LOAD_TASK_PREFIX,
        layer=LayerEnum.ENRICH,
        schema=CONTEXT,
        table_name=addresses_s2_geometry_mapping_table,
    ),
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": calculate_dejavu_id_job_path,
            "parameters": [
                ENV,
                DATALAKE_BUCKET,
                DAG_NAME,
                CONTEXT,
                addresses_s2_geometry_mapping_table,
                requests_limit,
            ],
        }
    },
)

sync_metadata_dejavu_task = datalake_task_group._build_metadata_sync_task(
    source=CONTEXT,
    sync_mode=datalake_task_group.SINGLE_TABLE,
    layer=LayerEnum.ENRICH.value,
    database_name=CONTEXT,
    table_name=addresses_s2_geometry_mapping_table,
    metadata_file_type=MetadataTypeEnum.LINEAGE.value,
)

condo_enrich_task_group = enrich_task_groups.pop('condo')

INNER_DEPENDENCIES = {

}

(
    task_groups_boundaries_without_inner_dependencies,
    inner_dependencies_task_groups_boundaries,
) = datalake_task_group.set_inner_dag_dependencies(
    task_flow_helper=TaskFlowHelper(),
    task_groups_boundaries=enrich_task_groups,
    dag_inner_dependencies=INNER_DEPENDENCIES,
)

chain(
    create_cluster_task,
    datalake_task_group.all_first_tasks(
        task_groups_boundaries_without_inner_dependencies
    )
    + datalake_task_group.first_tasks(inner_dependencies_task_groups_boundaries),
)

chain(
    datalake_task_group.all_last_tasks(
        task_groups_boundaries_without_inner_dependencies
    )
    + datalake_task_group.last_tasks(inner_dependencies_task_groups_boundaries),
    calculate_dejavu_id_task,
    sync_metadata_dejavu_task,
    datalake_task_group.first_tasks(condo_enrich_task_group),
)

sync_metadata_dejavu_task.set_downstream(
    datalake_task_group.first_tasks(condo_enrich_task_group)
)

external_bucket_task.set_upstream(
    datalake_task_group.first_tasks(condo_enrich_task_group)
)

for task in datalake_task_group.last_tasks(condo_enrich_task_group):
    task.set_downstream(
        terminate_cluster_task
    )

terminate_cluster_task.set_upstream(
    external_bucket_task
)
