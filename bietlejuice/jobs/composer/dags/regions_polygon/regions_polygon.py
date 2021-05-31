from datetime import datetime
import pendulum
import os

from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 8, 1, 0, 0, 0, tzinfo=LOCAL_TZ)

DAG_NAME = "regions_polygon"
DAG_ID = f"bietlejuice.{DAG_NAME}"
ENV = os.environ.get("ENVIRONMENT")

DATALAKE_BUCKET = Variable.get("datalake_bucket")
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_s3_bucket")
LOOKER_BUCKET = Variable.get("looker_bucket")
RELATIVE_FULL_QUERY_PATH = f"{DAG_NAME}/regions_polygon.sql"
POLYGONS_FILE_OUTPUT_PATH = f"s3://{LOOKER_BUCKET}/subregion_polygons_new"
POLYGONS_FILE_NAME = "5a_subregion_polygons.topojson"
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")

SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/{DAG_NAME}/"
LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)

CLUSTER_DESCRIPTION = Variable.get(
    "databricks_minimum_resources_cluster_spark_3", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

# databricks libraries
DEFAULT_LIBRARIES = Variable.get("bietlejuice_default_libraries", deserialize_json=True)
CUSTOM_LIBRARIES = [
    {"whl": f"{ARTIFACTS_S3_BUCKET}/geo_spark/geospark-1.3.2-py3-none-any.whl"},
    {"jar": f"{ARTIFACTS_S3_BUCKET}/geo_spark/geospark-1.3.2.jar"},
    {"jar": f"{ARTIFACTS_S3_BUCKET}/geo_spark/geospark-sql_2.3-1.3.2.jar"},
    {"jar": f"{ARTIFACTS_S3_BUCKET}/pytopojson/pytopojson-1.0.0-py3-none-any.whl"},
]
LIBRARIES_DESCRIPTION = DEFAULT_LIBRARIES + CUSTOM_LIBRARIES

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
