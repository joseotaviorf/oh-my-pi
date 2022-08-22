import pendulum

from datetime import datetime, timedelta
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)
from bietlejuice.base.airflow import BaseDAG, DAGOwnerEnum
from bietlejuice.services import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2020, 12, 2, 0, 0, 0, tzinfo=LOCAL_TZ)
MAIN_SCHEDULE_INTERVAL = "0 9 * * *"

DW_SCHEMA = "metrics"
CONTEXT = "shared_metrics"
DAG_NAME = f"dw_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"
EXECUTION_TIMEOUT_HOURS = 3.0


configs_service = ConfigurationService(DAG_NAME)
dw_bucket = configs_service.get_config("dw_bucket")
doc_md_chart_url = configs_service.get_config("doc_md_chart_url")
databricks_bietlejuice_repo_path = configs_service.get_config(
    "databricks_bietlejuice_repo_path"
)
metrics_path = configs_service.get_config("metrics_path")
spark_jobs_logs_path = configs_service.get_config("spark_jobs_logs_path")

spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base"
logs_output_path = "{}{}".format(spark_jobs_logs_path, DAG_ID)

CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = logs_output_path
default_libraries = configs_service.get_config("default_libraries")

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
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=default_libraries,
)

ctas_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id="create-table-as-select",
    json={
        "spark_python_task": {
            "python_file": f"{spark_jobs_path}/create_metrics_tables.py",
            "parameters": [DW_SCHEMA, "ENV_DW", metrics_path],
        }
    },
    execution_timeout=timedelta(hours=EXECUTION_TIMEOUT_HOURS),
)


terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

create_cluster_task >> ctas_task >> terminate_cluster_task
