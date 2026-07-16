from datetime import datetime, timedelta
from typing import List

import pendulum
from airflow.models import DAG
from airflow.operators.dummy_operator import DummyOperator
from databricks_plugin import (
    QuintoAndarDatabricksCheckJobTaskOperator,
    QuintoAndarDatabricksExecuteJobClusterOperator,
)

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.datasets.dataset_adder import DatasetAdder
from bietlejuice.base.databricks.cluster_permission_enum import ClusterPermissionEnum
from bietlejuice.base.databricks.databricks_group_name_enum import (
    DatabricksGroupNameEnum,
)
from bietlejuice.base.notification.gchat_callback import GchatCallback
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.dataset_service import DatasetService
from dags.atlas_db.vespucio_pipeline_table_names import Tables

VESPUCIO_PACKAGE_NAME = "vespucio"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2026, 7, 14, 0, 0, 0, tzinfo=LOCAL_TZ)

CONTEXT = "vespucio_pipeline_v2"
DAG_NAME = f"enrich_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"

EXECUTION_HOURS_TIMEOUT = 3.0

config_service = ConfigurationService(DAG_NAME)
artifacts_bucket = config_service.get_config("artifacts_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
output_location = config_service.get_config("vespucio_output_path")

VESPUCIO_PACKAGE_VERSION = config_service.get_config("vespucio_pipeline_version")
VESPUCIO_WHEEL_FILE = (
    f"{VESPUCIO_PACKAGE_NAME}-{VESPUCIO_PACKAGE_VERSION}-py3-none-any.whl"
)

CLUSTER_DESCRIPTION = config_service.get_config("custom_cluster")
CLUSTER_DESCRIPTION["spark_conf"].update(
    {"spark.metrics.namespace": "data_products.enrich_vespucio_pipeline_v2"}
)
CLUSTER_DESCRIPTION["spark_env_vars"]["OUTPUT_LOCATION"] = output_location
CLUSTER_DESCRIPTION["data_security_mode"] = "SINGLE_USER"
CLUSTER_DESCRIPTION["single_user_name"] = "{{ var.value.databricks_single_user_name }}"
CLUSTER_DESCRIPTION["spark_conf"]["spark.databricks.sql.initial.catalog.namespace"] = (
    "quintoandar_{{ var.value.environment }}"
)
CLUSTER_DESCRIPTION["driver_node_type_id"] = "r5a.4xlarge"
CLUSTER_DESCRIPTION["node_type_id"] = "c5a.4xlarge"
CLUSTER_DESCRIPTION["num_workers"] = 6

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    },
    {
        "group_name": DatabricksGroupNameEnum.SOFTWARE_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    },
]

LIBRARIES = [
    {"whl": f"{artifacts_bucket}/vespucio/{VESPUCIO_WHEEL_FILE}"},
]

DAG_DOCUMENTATION = config_service.get_config("dag_documentation")
DAG_OWNER = DAGOwnerEnum.DATA_ATLAS_DB
webhook_vespucio_pipeline_v2 = config_service.get_config("webhook_vespucio_pipeline_v2")
callback_by_task_failure = config_service.get_config("callback_by_task_failure")
callback_by_task_success = config_service.get_config("callback_by_task_success")

gchat_callback = GchatCallback(webhook_url_variable=webhook_vespucio_pipeline_v2)

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAG_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
        "on_success_callback": (
            gchat_callback.task_success_alert if callback_by_task_success else None
        ),
        "on_failure_callback": (
            gchat_callback.task_failure_alert if callback_by_task_failure else None
        ),
    },
    start_date=MAIN_START_DATE,
    schedule_interval=DatasetService.get_dag_datasets(DAG_ID),
    doc_md=BaseDAG.generate_doc_md_str(
        dag_name=DAG_NAME,
        doc_md_chart_url=doc_md_chart_url,
        dag_documentation=DAG_DOCUMENTATION,
        dag_owner=DAG_OWNER,
    ),
    params=BaseDAG.get_default_trigger_form_params(),
    on_success_callback=(
        gchat_callback.dag_success_alert if not callback_by_task_success else None
    ),
    on_failure_callback=(
        gchat_callback.dag_failure_alert if not callback_by_task_failure else None
    ),
)

execute_job_cluster_task = QuintoAndarDatabricksExecuteJobClusterOperator(
    databricks_conn_id="databricks_new",
    dag=dag,
    task_id="execute-job-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=LIBRARIES,
)

# Reprocessing guard task to ensure that the DAG does not run multiple times unnecessarily
DatasetAdder.attach_reprocessing_guard(execute_job_cluster_task)


def create_task(entry_point: str, parameters: List[str], task_id: str = None):
    return QuintoAndarDatabricksCheckJobTaskOperator(
        databricks_conn_id="databricks_new",
        dag=dag,
        task_id=(task_id or entry_point).replace("-", "-"),
        json={
            "python_wheel_task": {
                "package_name": VESPUCIO_PACKAGE_NAME,
                "entry_point": entry_point,
                "parameters": parameters,
            }
        },
        execution_timeout=timedelta(hours=EXECUTION_HOURS_TIMEOUT),
    )


# v1's registry sources are duplicated here (own _v2 tables) so this DAG runs independently
# of enrich_vespucio_pipeline. geocode_step_cache / address_details_hasher_link /
# staged_parsed_complements are NOT duplicated: they are v1 pipeline outputs (live geocoding
# calls, address hashing) and are reused as-is to avoid doubling that cost.
source_tasks = [
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=cnefe_house.sql",
            f"--output_table={Tables.source_cnefe_houses_v2}",
        ],
        task_id="cnefe_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=ebdb_house.sql",
            f"--output_table={Tables.source_ebdb_houses_v2}",
        ],
        task_id="ebdb_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=navent_house_composed.sql",
            f"--output_table={Tables.source_navent_houses_composed_v2}",
        ],
        task_id="navent_house_composed",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=union_house.sql",
            f"--output_table={Tables.source_union_houses_v2}",
        ],
        task_id="union_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=idactum_house.sql",
            f"--output_table={Tables.source_idactum_houses_v2}",
        ],
        task_id="idactum_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=idactum_transactions.sql",
            f"--output_table={Tables.source_idactum_transactions_v2}",
        ],
        task_id="idactum_transactions",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=itbi_house.sql",
            f"--output_table={Tables.source_itbi_houses_v2}",
        ],
        task_id="itbi_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=iptu_house.sql",
            f"--output_table={Tables.source_iptu_houses_v2}",
        ],
        task_id="iptu_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=zap_imoveis_house.sql",
            f"--output_table={Tables.source_zap_imoveis_houses_v2}",
        ],
        task_id="zap_house",
    ),
]

registry_step_task = create_task(
    entry_point="core_v2_registry_step",
    parameters=[
        f"--input_source_cnefe_houses={Tables.source_cnefe_houses_v2}",
        f"--input_source_ebdb_houses={Tables.source_ebdb_houses_v2}",
        f"--input_source_idactum_houses={Tables.source_idactum_houses_v2}",
        f"--input_source_idactum_transactions={Tables.source_idactum_transactions_v2}",
        f"--input_source_iptu_houses={Tables.source_iptu_houses_v2}",
        f"--input_source_itbi_houses={Tables.source_itbi_houses_v2}",
        f"--input_source_navent_houses_composed={Tables.source_navent_houses_composed_v2}",
        f"--input_source_union_houses={Tables.source_union_houses_v2}",
        f"--input_source_zap_imoveis_houses={Tables.source_zap_imoveis_houses_v2}",
        "--overwrite_schema",
        f"--output_registry={Tables.registry_step_v2}",
    ],
)

normalization_step_task = create_task(
    entry_point="core_v2_normalization_step",
    parameters=[
        f"--input_registry={Tables.registry_step_v2}",
        "--overwrite_schema",
        f"--output_normalized={Tables.normalization_step_v2}",
    ],
)

address_enrich_step_task = create_task(
    entry_point="core_v2_address_enrich_step",
    parameters=[
        f"--input_normalized={Tables.normalization_step_v2}",
        f"--input_geocode_cache={Tables.geocode_step_cache}",
        f"--input_address_details_hasher_link={Tables.address_details_hasher_link}",
        f"--input_staged_parsed_complements={Tables.staged_parsed_complements}",
        f"--input_source_cnefe_houses={Tables.source_cnefe_houses_v2}",
        f"--input_source_iptu_houses={Tables.source_iptu_houses_v2}",
        "--overwrite_schema",
        f"--output_enriched={Tables.address_enrich_step_v2}",
    ],
)

vespucio_v2_pipeline_complete_task = DummyOperator(
    task_id="vespucio-v2-pipeline-complete",
    dag=dag,
)
DatasetAdder.attach_dataset_to_task(vespucio_v2_pipeline_complete_task)


execute_job_cluster_task >> source_tasks
source_tasks >> registry_step_task
registry_step_task >> normalization_step_task
normalization_step_task >> address_enrich_step_task
address_enrich_step_task >> vespucio_v2_pipeline_complete_task
