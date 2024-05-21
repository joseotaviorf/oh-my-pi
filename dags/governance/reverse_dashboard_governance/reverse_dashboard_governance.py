from datetime import datetime
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from pendulum import timezone
import os

from airflow.utils.helpers import chain
from airflow.models import DAG
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.airflow.task_groups.reverse_task_group import ReverseTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

# ENV setup
ENV = os.environ.get("ENVIRONMENT")

# DAG and Jobs params setup
SOURCE = "dashboard_governance"
DAG_NAME = f"reverse_{SOURCE}"
DAG_ID = f"bietlejuice.{DAG_NAME}"

MAIN_START_DATE = datetime(2022, 7, 12, 0, 0, 0, tzinfo=timezone("America/Sao_Paulo"))

config_service = ConfigurationService(DAG_NAME)

# S3 path setup
datalake_bucket = config_service.get_config("datalake_bucket")
s3_prefix = config_service.get_config("databricks_bietlejuice_repo_path")
base_spark_jobs_path = f"{s3_prefix}/spark_jobs/base/"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")

reverse_spark_job_path = (
    f"{s3_prefix}/spark_jobs/{DAG_NAME}/load_dashboard_governance_into_mp.py"
)  ## TODO deprecate when migrating dashboards

reverse_asset_spark_job_path = (
    f"{s3_prefix}/spark_jobs/{DAG_NAME}/load_data_assets_into_mp.py"
)



CLUSTER_DESCRIPTION = config_service.get_config(
    "databricks_12_2_min_general_photon_cluster"
)
default_libraries = config_service.get_config("default_libraries")

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_GOVERNANCE,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=None,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID, ENV=ENV
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=default_libraries,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)


task_group = ReverseTaskGroup(
    dag=dag,
    env=ENV,
    s3_bucket=datalake_bucket,
    relative_query_path=DAG_NAME,
    spark_jobs_path=base_spark_jobs_path,
)

submit_metadata_propagator_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="load_dashboard_governance_into_mp",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": reverse_spark_job_path,
            "parameters": [ENV, "{{ ds }}"],
        }
    },
)

datalake_task_groups = task_group.build_task_group_from_sql_files(
    layer=LayerEnum.REVERSE,
    source_database_base_name=SOURCE,
    target_database_base_name=SOURCE,
    is_incremental=False,
    execution_date="{{ ds }}",
)   

send_assets_to_metadata_propagator_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="load_data_assets_into_mp",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": reverse_asset_spark_job_path,
            "parameters": [ENV, "--data_assets", "dashboard", "chart", "dataset"],
        }
    },
)

chain(create_cluster_task, submit_metadata_propagator_task)
chain(create_cluster_task, ReverseTaskGroup.all_first_tasks(datalake_task_groups))

chain(ReverseTaskGroup.all_first_tasks(datalake_task_groups), send_assets_to_metadata_propagator_task)

chain(submit_metadata_propagator_task, terminate_cluster_task)
chain(send_assets_to_metadata_propagator_task, terminate_cluster_task)
