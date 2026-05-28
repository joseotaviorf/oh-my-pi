from datetime import datetime, timedelta

import pendulum
from airflow.models import DAG
from airflow.operators.python import PythonOperator
from databricks_plugin import (
    QuintoAndarDatabricksCheckJobTaskOperator,
    QuintoAndarDatabricksExecuteJobClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.services.configuration_service import ConfigurationService
from dags.publisher_xp.alias_classifieds_common import (
    BASE_ALIAS_CLASSIFIEDS_PARAMS,
    BASE_ALIAS_CLASSIFIEDS_PUBLISHER_PARAMS,
    DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    VESPUCIO_PACKAGE_NAME,
)

LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2025, 1, 1, 0, 0, 0, tzinfo=LOCAL_TZ)

DAG_NAME = "alias_classifieds_on_demand"
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
    {"spark.metrics.namespace": "data_products.alias_classifieds_on_demand"}
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

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAG_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=None,
    catchup=False,
    doc_md=BaseDAG.generate_doc_md_str(
        dag_name=DAG_NAME,
        doc_md_chart_url=doc_md_chart_url,
        dag_documentation=DAG_DOCUMENTATION,
        dag_owner=DAG_OWNER,
    ),
    params=BaseDAG.get_default_trigger_form_params(),
    render_template_as_native_obj=True,
)

execute_job_cluster_task = QuintoAndarDatabricksExecuteJobClusterOperator(
    databricks_conn_id="databricks_new",
    dag=dag,
    task_id="execute-job-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=LIBRARIES,
)


def _build_run_params(**context):
    """Build task parameters. Requires company_uuid or publisher_id in dag_run.conf."""
    conf = context["dag_run"].conf or {}
    company_uuid = conf.get("company_uuid")
    publisher_id = conf.get("publisher_id")

    if not company_uuid and not publisher_id:
        raise ValueError(
            "On-demand run requires 'company_uuid' or 'publisher_id' in dag_run.conf. "
            'Example: {"company_uuid": "<UUID>"} or {"publisher_id": "<ID>"}'
        )

    alias_classifieds_params = list(BASE_ALIAS_CLASSIFIEDS_PARAMS)
    alias_classifieds_publisher_params = list(
        BASE_ALIAS_CLASSIFIEDS_PUBLISHER_PARAMS
    ) + [
        f"--bootstrap_servers={kafka_bootstrap_servers}",
        f"--topic={kafka_topic}",
    ]

    if company_uuid:
        alias_classifieds_params.append(f"--company_uuid={company_uuid}")
        alias_classifieds_publisher_params.append(f"--company_uuid={company_uuid}")
    if publisher_id:
        alias_classifieds_params.append(f"--publisher_id={publisher_id}")

    context["ti"].xcom_push(
        key="alias_classifieds_params", value=alias_classifieds_params
    )
    context["ti"].xcom_push(
        key="alias_classifieds_publisher_params",
        value=alias_classifieds_publisher_params,
    )


build_run_params_task = PythonOperator(
    task_id="build_run_params",
    python_callable=_build_run_params,
    dag=dag,
)

alias_classifieds_task = QuintoAndarDatabricksCheckJobTaskOperator(
    databricks_conn_id="databricks_new",
    dag=dag,
    task_id="alias_classifieds",
    json={
        "python_wheel_task": {
            "package_name": VESPUCIO_PACKAGE_NAME,
            "entry_point": "plugins_alias_classifieds",
            "parameters": "{{ ti.xcom_pull(task_ids='build_run_params', key='alias_classifieds_params') }}",
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
            "parameters": "{{ ti.xcom_pull(task_ids='build_run_params', key='alias_classifieds_publisher_params') }}",
        }
    },
    execution_timeout=timedelta(hours=EXECUTION_HOURS_TIMEOUT),
)

(
    build_run_params_task
    >> execute_job_cluster_task
    >> alias_classifieds_task
    >> alias_classifieds_publisher_task
)
