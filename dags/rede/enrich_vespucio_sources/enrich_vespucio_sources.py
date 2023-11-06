import os
from datetime import datetime, timedelta
from bietlejuice.base.airflow.base_task_group import BaseTaskGroup
from bietlejuice.base.pipeline.layer_enum import LayerEnum

import pendulum
from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksExecuteJobClusterOperator,
    QuintoAndarDatabricksCheckJobTaskOperator,
)
from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.databricks.cluster_permission_enum import ClusterPermissionEnum
from bietlejuice.base.databricks.databricks_group_name_enum import (
    DatabricksGroupNameEnum,
)
from bietlejuice.services.configuration_service import ConfigurationService


LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2021, 8, 24, 0, 0, 0, tzinfo=LOCAL_TZ)

CONTEXT = "vespucio_sources"
DAG_NAME = f"enrich_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"

ENV = os.environ.get("ENVIRONMENT")
EXECUTION_HOURS_TIMEOUT = 2.0

config_service = ConfigurationService(DAG_NAME)
artifacts_bucket = config_service.get_config("artifacts_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
spark_job_path = (
    f"{databricks_bietlejuice_repo_path}/spark_jobs/{DAG_NAME}/load_{CONTEXT}.py"
)

CLUSTER_DESCRIPTION = config_service.get_config("databricks_13_3_med_general_cluster")
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
LIBRARIES = [
    {
        "whl": f"{artifacts_bucket}/vespucio/"
        "quintoandar_vespucio-0.0.3-py3-none-any.whl"
    }
]
DAG_DOCUMENTATION = config_service.get_config("dag_documentation")
DAG_OWNER = DAGOwnerEnum.DATA_REDE

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAG_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=None,
    doc_md=BaseDAG.generate_doc_md_str(
        dag_name=DAG_NAME,
        doc_md_chart_url=doc_md_chart_url,
        dag_documentation=DAG_DOCUMENTATION,
        dag_owner=DAG_OWNER,
    ),
)

execute_job_cluster_task = QuintoAndarDatabricksExecuteJobClusterOperator(
    databricks_conn_id="databricks_job_cluster",
    dag=dag,
    task_id="execute-job-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=LIBRARIES,
)

tables = config_service.get_config("tables")

for table_name in tables:
    load_table_task = QuintoAndarDatabricksCheckJobTaskOperator(
        databricks_conn_id="databricks_job_cluster",
        dag=dag,
        task_id=BaseTaskGroup.generate_default_task_id(
            task_prefix=BaseTaskGroup.LOAD_TASK_PREFIX,
            layer=LayerEnum.ENRICH,
            schema=CONTEXT,
            table_name=table_name,
        ),
        json={
            "spark_python_task": {
                "python_file": spark_job_path,
                "parameters": [table_name]
            }
        },
        execution_timeout=timedelta(hours=EXECUTION_HOURS_TIMEOUT),
    )

    execute_job_cluster_task >> load_table_task