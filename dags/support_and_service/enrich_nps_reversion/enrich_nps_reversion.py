import os
from datetime import datetime
from pendulum import timezone

from airflow.models import DAG
from airflow.utils.helpers import chain
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.formatters import StringFormatter
from bietlejuice.services.configuration_service import ConfigurationService


ENV = os.environ.get("ENVIRONMENT")
SOURCE = "nps_reversion"
CONTEXT = SOURCE
DAG_NAME = f"enrich_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
DAG_OWNER = DAGOwnerEnum.DATA_SS

MAIN_START_DATE = datetime(2023, 3, 6, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = None

config_service = ConfigurationService(DAG_NAME)

athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")


output_tenant_table_name = config_service.get_config(
    "offboarding_tenant_output_table_name"
)
slugged_tenant_table_name = StringFormatter.slugify(output_tenant_table_name)
enrich_tenant_spark_job_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/{DAG_NAME}/load_nps_reversion_tenant_enrich.py"

output_landlord_table_name = config_service.get_config(
    "offboarding_landlord_output_table_name"
)
slugged_landlord_table_name = StringFormatter.slugify(output_landlord_table_name)
enrich_landlord_spark_job_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/{DAG_NAME}/load_nps_reversion_landlord_enrich.py"

partitions = config_service.get_config("input_partitions")
cluster_configuration = config_service.get_config("databricks_10_4_med_general_cluster")
default_libraries = config_service.get_config("default_libraries")
custom_libraries = config_service.get_config("custom_libraries")
dag_documentation = config_service.get_config("dag_documentation")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAG_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    catchup=False,
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.generate_doc_md_str(
        dag_name=DAG_NAME,
        doc_md_chart_url=doc_md_chart_url,
        dag_documentation=dag_documentation,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        dag_owner=DAG_OWNER,
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_configuration,
    libraries=default_libraries + custom_libraries,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

task_group = DatalakeTaskGroup(
    dag=dag,
    env=ENV,
    datalake_bucket=datalake_bucket,
    relative_query_path=DAG_NAME,
    spark_jobs_path=base_spark_jobs_path,
    athena_query_result_location=athena_query_results_bucket,
)

enrich_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.ENRICH,
    source_database_base_name=CONTEXT,
    target_database_base_name=CONTEXT,
    is_incremental=True,
    has_create_external_table_task=False,
    partitions=partitions,
)

load_tenant_model_output_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id=f"load-{LayerEnum.ENRICH.value}-{slugged_tenant_table_name}",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": enrich_tenant_spark_job_path,
            "parameters": [ENV, datalake_bucket, CONTEXT, CONTEXT, "{{ ds }}"],
        }
    },
)

sync_tenant_model_output_table_structure = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"sync-hive-metastore-{LayerEnum.ENRICH.value}-{slugged_tenant_table_name}-structure",
    json={
        "spark_python_task": {
            "python_file": f"{base_spark_jobs_path}/sync_metastore_tables_structure.py",
            "parameters": [
                datalake_bucket,
                LayerEnum.ENRICH.value,
                CONTEXT,
                "--table-name",
                output_tenant_table_name,
            ],
        }
    },
)

sync_tenant_model_output_partitions = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"sync-hive-metastore-{LayerEnum.ENRICH.value}-{slugged_tenant_table_name}-partitions",
    json={
        "spark_python_task": {
            "python_file": f"{base_spark_jobs_path}/sync_metastore_tables_partitions.py",
            "parameters": [
                datalake_bucket,
                LayerEnum.ENRICH.value,
                CONTEXT,
                "--table-name",
                output_tenant_table_name,
            ],
        }
    },
)

propagate_tenant_model_output_metadata = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"propagate-table-metadata-{LayerEnum.ENRICH.value}-{slugged_tenant_table_name}",
    json={
        "spark_python_task": {
            "python_file": f"{base_spark_jobs_path}/propagate_table_metadata.py",
            "parameters": [
                LayerEnum.ENRICH.value,
                MetadataTypeEnum.LINEAGE.value,
                CONTEXT,
                output_tenant_table_name,
            ],
        }
    },
)

chain(
    load_tenant_model_output_task,
    sync_tenant_model_output_table_structure,
    sync_tenant_model_output_partitions,
    propagate_tenant_model_output_metadata,
    terminate_cluster_task,
)

chain(create_cluster_task, DatalakeTaskGroup.all_first_tasks(enrich_task_groups))
load_tenant_model_output_task.set_upstream(
    DatalakeTaskGroup.all_last_tasks(enrich_task_groups)
)

load_landlord_model_output_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id=f"load-{LayerEnum.ENRICH.value}-{slugged_landlord_table_name}",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": enrich_landlord_spark_job_path,
            "parameters": [ENV, datalake_bucket, CONTEXT, CONTEXT, "{{ ds }}"],
        }
    },
)

sync_landlord_model_output_table_structure = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"sync-hive-metastore-{LayerEnum.ENRICH.value}-{slugged_landlord_table_name}-structure",
    json={
        "spark_python_task": {
            "python_file": f"{base_spark_jobs_path}/sync_metastore_tables_structure.py",
            "parameters": [
                datalake_bucket,
                LayerEnum.ENRICH.value,
                CONTEXT,
                "--table-name",
                output_landlord_table_name,
            ],
        }
    },
)

sync_landlord_model_output_partitions = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"sync-hive-metastore-{LayerEnum.ENRICH.value}-{slugged_landlord_table_name}-partitions",
    json={
        "spark_python_task": {
            "python_file": f"{base_spark_jobs_path}/sync_metastore_tables_partitions.py",
            "parameters": [
                datalake_bucket,
                LayerEnum.ENRICH.value,
                CONTEXT,
                "--table-name",
                output_landlord_table_name,
            ],
        }
    },
)

propagate_landlord_model_output_metadata = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"propagate-table-metadata-{LayerEnum.ENRICH.value}-{slugged_landlord_table_name}",
    json={
        "spark_python_task": {
            "python_file": f"{base_spark_jobs_path}/propagate_table_metadata.py",
            "parameters": [
                LayerEnum.ENRICH.value,
                MetadataTypeEnum.LINEAGE.value,
                CONTEXT,
                output_landlord_table_name,
            ],
        }
    },
)

chain(
    load_landlord_model_output_task,
    sync_landlord_model_output_table_structure,
    sync_landlord_model_output_partitions,
    propagate_landlord_model_output_metadata,
    terminate_cluster_task,
)


load_landlord_model_output_task.set_upstream(
    DatalakeTaskGroup.all_last_tasks(enrich_task_groups)
)
