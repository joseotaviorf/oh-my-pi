from datetime import datetime
import pendulum
import os

from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 8, 1, 0, 0, 0, tzinfo=LOCAL_TZ)

DAG_NAME = "regions_polygon"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = os.environ.get("ENVIRONMENT")

config_service = ConfigurationService(DAG_NAME)

DATALAKE_BUCKET = config_service.get_config("datalake_bucket")
DOC_MD_CHART_URL = config_service.get_config("doc_md_chart_url")

ARTIFACTS_S3_BUCKET = Variable.get("artifacts_s3_bucket")
LOOKER_BUCKET = Variable.get("looker_bucket")

# This layer does not exist, it was added in this DAG because it is out of pattern and
# a layer name is needed so the validation flows does not break
RELATIVE_FULL_QUERY_PATH = f"{DAG_NAME}/queries/enrich_for_looker/regions_polygon.sql"
POLYGONS_FILE_OUTPUT_PATH = f"s3://{LOOKER_BUCKET}/subregion_polygons_new"
POLYGONS_FILE_NAME = "5a_subregion_polygons.topojson"

DATBRICKS_BIETLEJUICE_REPO_PATH = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)

SPARK_JOBS_PATH = f"{DATBRICKS_BIETLEJUICE_REPO_PATH}/spark_jobs/{DAG_NAME}/"
SPARK_JOBS_LOGS_PATH = config_service.get_config("spark_jobs_logs_path")

CLUSTER_DESCRIPTION = Variable.get(
    "databricks_minimum_resources_cluster_spark_3", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"][
    "destination"
] = f"{SPARK_JOBS_LOGS_PATH}{DAG_ID}"

# databricks libraries
DEFAULT_LIBRARIES = config_service.get_config("default_libraries")
CUSTOM_LIBRARIES = [
    {"whl": f"{ARTIFACTS_S3_BUCKET}/geo_spark/geospark-1.3.2-py3-none-any.whl"},
    {"jar": f"{ARTIFACTS_S3_BUCKET}/geo_spark/geospark-1.3.2.jar"},
    {"jar": f"{ARTIFACTS_S3_BUCKET}/geo_spark/geospark-sql_2.3-1.3.2.jar"},
    {"jar": f"{ARTIFACTS_S3_BUCKET}/pytopojson/pytopojson-1.0.0-py3-none-any.whl"},
]
LIBRARIES_DESCRIPTION = DEFAULT_LIBRARIES + CUSTOM_LIBRARIES

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_FOR_RENT,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=None,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=DOC_MD_CHART_URL, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

regions_polygon_topojson_to_s3_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="regions-polygon-topojson-to-datalake",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "create_regions_polygon_topojson.py",
            "parameters": [
                ENV,
                DATALAKE_BUCKET,
                RELATIVE_FULL_QUERY_PATH,
                POLYGONS_FILE_OUTPUT_PATH,
                POLYGONS_FILE_NAME,
                "{{ ds }}",
            ],
        }
    },
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

create_cluster_task >> regions_polygon_topojson_to_s3_task >> terminate_cluster_task
