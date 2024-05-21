import os
from datetime import datetime
from pendulum import timezone

from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

SOURCE = "regions_polygon"
CONTEXT = f"reverse_{SOURCE}"
DAG_ID = f"bietlejuice.{CONTEXT}"
MAIN_START_DATE = datetime(2020, 8, 1, tzinfo=timezone("America/Sao_Paulo"))
CLUSTER_DESCRIPTION = "custom_cluster"
CUSTOM_LIBRARIES = [
    {
        "maven": {
            "coordinates": "org.apache.sedona:sedona-python-adapter-3.0_2.12:1.2.1-incubating"
        }
    },
    {
        "maven": {
            "coordinates": "org.apache.sedona:sedona-viz-3.0_2.12:1.2.1-incubating"
        }
    },
    {"maven": {"coordinates": "org.datasyslab:geotools-wrapper:1.3.0-27.2"}},
    {"pypi": {"package": "pytopojson==1.0.0"}},
    {"pypi": {"package": "apache-sedona"}},
]

config_service = ConfigurationService(CONTEXT)
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
raw_spark_job_file = f"{databricks_bietlejuice_repo_path}/spark_jobs/{CONTEXT}/create_regions_polygon_topojson.py"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
cluster_configuration = config_service.get_config(CLUSTER_DESCRIPTION)
default_libraries = config_service.get_config("default_libraries")

output_file_path = config_service.get_config("output_file_path")
output_file_name = config_service.get_config("output_file_name")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
ENV = os.environ.get("ENVIRONMENT")

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FOR_RENT,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=None,
    doc_md=BaseDAG.get_dag_doc(CONTEXT).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_configuration,
    libraries=default_libraries + CUSTOM_LIBRARIES,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

regions_polygon_topojson_to_s3_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="regions-polygon-topojson-to-datalake",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_job_file,
            "parameters": [
                ENV,
                datalake_bucket,
                SOURCE,
                output_file_path,
                output_file_name,
                "{{ ds }}",
            ],
        }
    },
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

create_cluster_task >> regions_polygon_topojson_to_s3_task >> terminate_cluster_task
