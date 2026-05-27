from datetime import datetime, timedelta

import pendulum
from airflow.models import DAG
from databricks_plugin import (
    QuintoAndarDatabricksCheckJobTaskOperator,
    QuintoAndarDatabricksExecuteJobClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.datasets.dataset_adder import DatasetAdder
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.dataset_service import DatasetService
from dags.publisher_xp.alias_classifieds_common import (
    BASE_ALIAS_CLASSIFIEDS_PARAMS,
    BASE_ALIAS_CLASSIFIEDS_PUBLISHER_PARAMS,
    DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    VESPUCIO_PACKAGE_NAME,
)

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2025, 1, 1, 0, 0, 0, tzinfo=LOCAL_TZ)

DAG_NAME = "alias_classifieds"
DAG_ID = f"bietlejuice.{DAG_NAME}"

EXECUTION_HOURS_TIMEOUT = 3.0

config_service = ConfigurationService(DAG_NAME)
artifacts_bucket = config_service.get_config("artifacts_bucket")
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
output_location = config_service.get_config("vespucio_output_path")

VESPUCIO_PACKAGE_VERSION = config_service.get_config("vespucio_pipeline_version")
VESPUCIO_WHEEL_FILE = (
    f"{VESPUCIO_PACKAGE_NAME}-{VESPUCIO_PACKAGE_VERSION}-py3-none-any.whl"
)

CLUSTER_DESCRIPTION = config_service.get_config("custom_cluster")
CLUSTER_DESCRIPTION["spark_conf"].update(
    {"spark.metrics.namespace": "data_products.alias_classifieds"}
)
CLUSTER_DESCRIPTION["spark_env_vars"]["OUTPUT_LOCATION"] = output_location
CLUSTER_DESCRIPTION["data_security_mode"] = "SINGLE_USER"
CLUSTER_DESCRIPTION["single_user_name"] = "{{ var.value.databricks_single_user_name }}"
CLUSTER_DESCRIPTION["spark_conf"]["spark.databricks.sql.initial.catalog.namespace"] = (
    "quintoandar_{{ var.value.environment }}"
)

LIBRARIES = [
    {"whl": f"{artifacts_bucket}/vespucio/{VESPUCIO_WHEEL_FILE}"},
    {"pypi": {"package": "networkx==3.2.1"}},
]

DAG_DOCUMENTATION = config_service.get_config("dag_documentation")
DAG_OWNER = DAGOwnerEnum.DATA_PUBLISHER_XP

kafka_bootstrap_servers = config_service.get_config("kafka_bootstrap_servers")
kafka_topic = config_service.get_config("kafka_topic")

ALIAS_CLASSIFIEDS_PARAMS = list(BASE_ALIAS_CLASSIFIEDS_PARAMS)

ALIAS_CLASSIFIEDS_PUBLISHER_PARAMS = list(BASE_ALIAS_CLASSIFIEDS_PUBLISHER_PARAMS) + [
    f"--bootstrap_servers={kafka_bootstrap_servers}",
    f"--topic={kafka_topic}",
]

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAG_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=DatasetService.get_dag_datasets(DAG_ID),
    catchup=False,
    doc_md=BaseDAG.generate_doc_md_str(
        dag_name=DAG_NAME,
        doc_md_chart_url=doc_md_chart_url,
        dag_documentation=DAG_DOCUMENTATION,
        dag_owner=DAG_OWNER,
    ),
    params=BaseDAG.get_default_trigger_form_params(),
)

execute_job_cluster_task = QuintoAndarDatabricksExecuteJobClusterOperator(
    databricks_conn_id="databricks_new",
    dag=dag,
    task_id="execute-job-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=LIBRARIES,
)

DatasetAdder.attach_reprocessing_guard(execute_job_cluster_task)

alias_classifieds_task = QuintoAndarDatabricksCheckJobTaskOperator(
    databricks_conn_id="databricks_new",
    dag=dag,
    task_id="alias_classifieds",
    json={
        "python_wheel_task": {
            "package_name": VESPUCIO_PACKAGE_NAME,
            "entry_point": "plugins_alias_classifieds",
            "parameters": ALIAS_CLASSIFIEDS_PARAMS,
        }
    },
    execution_timeout=timedelta(hours=EXECUTION_HOURS_TIMEOUT),
)

alias_classifieds_publisher_task = QuintoAndarDatabricksCheckJobTaskOperator(
    databricks_conn_id="databricks_new",
    dag=dag,
    task_id="alias_classifieds_publisher",
    json={
        "python_wheel_task": {
            "package_name": VESPUCIO_PACKAGE_NAME,
            "entry_point": "plugins_alias_classifieds_publisher",
            "parameters": ALIAS_CLASSIFIEDS_PUBLISHER_PARAMS,
        }
    },
    execution_timeout=timedelta(hours=EXECUTION_HOURS_TIMEOUT),
)

execute_job_cluster_task >> alias_classifieds_task >> alias_classifieds_publisher_task
