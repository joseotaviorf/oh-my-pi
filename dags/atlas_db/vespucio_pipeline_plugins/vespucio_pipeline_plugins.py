import os
from datetime import datetime, timedelta
from typing import List

import pendulum
from airflow.models import DAG
from airflow.operators.dummy_operator import DummyOperator
from airflow.utils.helpers import chain
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
MAIN_START_DATE = datetime(2021, 8, 24, 0, 0, 0, tzinfo=LOCAL_TZ)

DAG_NAME = "vespucio_pipeline_plugins"
DAG_ID = f"bietlejuice.{DAG_NAME}"

ENV = os.environ.get("ENVIRONMENT")
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
    {"spark.metrics.namespace": "data_products.vespucio_pipeline_plugins"}
)
CLUSTER_DESCRIPTION["spark_env_vars"]["OUTPUT_LOCATION"] = output_location
CLUSTER_DESCRIPTION["data_security_mode"] = "SINGLE_USER"
CLUSTER_DESCRIPTION["single_user_name"] = "{{ var.value.databricks_single_user_name }}"
CLUSTER_DESCRIPTION["spark_conf"]["spark.databricks.sql.initial.catalog.namespace"] = (
    "quintoandar_{{ var.value.environment }}"
)

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
    {"pypi": {"package": "networkx==3.2.1"}},
]

DAG_DOCUMENTATION = config_service.get_config("dag_documentation")
DAG_OWNER = DAGOwnerEnum.DATA_ATLAS_DB
webhook_vespucio_pipeline = config_service.get_config("webhook_vespucio_pipeline")
callback_by_task_failure = config_service.get_config("callback_by_task_failure")
callback_by_task_success = config_service.get_config("callback_by_task_success")

gchat_callback = GchatCallback(webhook_url_variable=webhook_vespucio_pipeline)

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


plugin_tasks = [
    create_task(
        entry_point="plugins_compound_indexer",
        parameters=[
            f"--elasticsearch_url={config_service.get_config('elastic_search_url')}",
            f"--update_alias",
            f"--delete_old_indices",
            f"--input_condo_compounds={Tables.condo_compounds}",
            f"--input_house_compounds={Tables.house_compounds}",
            f"--input_geocode_cache={Tables.geocode_step_cache}",
            f"--output_index_prefix=vespucio_prod",
            "--number_of_shards=3",
            "--number_of_replicas=2",
        ],
    ),
    create_task(
        entry_point="plugins_address_details_indexer",
        parameters=[
            f"--elasticsearch_url={config_service.get_config('elastic_search_url')}",
            f"--update_alias",
            f"--delete_old_indices",
            f"--input_house_compounds={Tables.house_compounds}",
            f"--output_index_prefix=vespucio_prod_address_details",
            "--number_of_shards=1",
            "--number_of_replicas=2",
        ],
    ),
    create_task(
        entry_point="plugins_rede_house_enrichment_consolidate",
        parameters=[
            f"--sqs_queue_url={config_service.get_config('sqs_url_house_enrichment')}",
            f"--sqs_region=us-east-1",
            f"--sqs_batch_size=10",
            f"--sqs_num_writers=10",
            f"--input_ebdb_house_enrichment={Tables.ebdb_clean_house_enrichment}",
            f"--input_condo_compounds={Tables.condo_compounds}",
            f"--input_house_compounds={Tables.house_compounds}",
        ],
    ),
    create_task(
        entry_point="plugins_seo_neighborhood_recommendation",
        parameters=[
            f"--input_listings={Tables.listings}",
            f"--input_houses={Tables.ebdb_clean_house}",
            f"--input_regions={Tables.ebdb_clean_region}",
            f"--input_map_regions={Tables.ebdb_clean_map_region}",
            f"--output_database=neighborhood_recommendation_vespucio_plugin",
            f"--output_listings_agg_by_neighborhood=listings_agg_by_neighborhood",
            f"--output_listings_agg_by_city=listings_agg_by_city",
            f"--output_listings_agg_ordered_by_count=listings_agg_ordered_by_count",
            f"--output_nearest_neighborhoods=nearest_neighborhoods",
            f"--output_keys_and_values_to_city_slug=keys_and_values_to_city_slug",
            f"--output_keys_and_values_to_neighborhood_slug=keys_and_values_to_neighborhood_slug",
            f"--output_price_by_neighborhood_slug=price_by_neighborhood_slug",
            f"--env={ENV}",
            f"--overwrite_schema",
        ],
    ),
    create_task(
        entry_point="plugins_property_search_indexer",
        parameters=[
            f"--elasticsearch_url={config_service.get_config('elastic_search_url')}",
            f"--update_alias",
            f"--delete_old_indices",
            f"--input_house_compounds={Tables.house_compounds}",
            f"--output_index_prefix=vespucio_prod",
            "--number_of_shards=3",
            "--number_of_replicas=2",
        ],
    ),
]

zordominium_tasks = [
    create_task(
        entry_point="plugins_zordominium",
        parameters=[
            f"--operation=both",
            f"--env={ENV}",
            f"--stage_db=zordominium_vespucio_plugin",
            f"--remove_old_condos=False",
        ],
    ),
    create_task(
        entry_point="plugins_condo_by_region",
        parameters=[
            f"--input_condos={Tables.zordominium_compounds}",
            f"--input_listings={Tables.listings}",
            f"--output_database=condos_by_region_plugin",
            "--operation=all",
            f"--env={ENV}",
        ],
    ),
]

classifieds_tasks = [
    create_task(
        entry_point="plugins_classifieds_house_id",
        parameters=[
            f"--input_listing_compound={Tables.listings}",
            f"--input_classifieds_house_id={Tables.classifieds_house_id}",
            f"--output_classifieds_house_id={Tables.classifieds_house_id}",
        ],
    ),
    create_task(
        entry_point="plugins_classifieds",
        parameters=[
            f"--overwrite_schema",
            f"--input_condo_compound={Tables.condo_compounds}",
            f"--input_house_compound={Tables.house_compounds}",
            f"--input_listing_compound={Tables.listings}",
            f"--input_zordominium_compound={Tables.zordominium_compounds}",
            f"--output_classified_compound={Tables.classified_compounds}",
        ],
    ),
    create_task(
        entry_point="plugins_classified_indexer",
        parameters=[
            f"--elasticsearch_url={config_service.get_config('elastic_search_url')}",
            f"--update_alias",
            f"--delete_old_indices",
            f"--input_classifieds={Tables.classified_compounds}",
            f"--output_index_prefix=vespucio_prod",
            f"--number_of_shards=4",
            f"--number_of_replicas=2",
            f"--refresh_interval=60",
        ],
    ),
]

classifieds_v2_tasks = [
    create_task(
        entry_point="plugins_classifieds_v2",
        parameters=[
            f"--input_condo_compound={Tables.condo_compounds}",
            f"--input_house_compound={Tables.house_compounds}",
            f"--input_listing_compound={Tables.listings}",
            f"--input_zordominium_compound={Tables.zordominium_compounds}",
            f"--input_region_table={Tables.ebdb_clean_region}",
            f"--input_state_table={Tables.ebdb_clean_state}",
            f"--input_country_table={Tables.ebdb_country_table}",
            f"--input_navent_source_table={Tables.source_navent_houses_composed}",
            f"--input_classified_house_id_table={Tables.classifieds_house_id}",
            f"--input_navent_publisher_reputation_table={Tables.source_navent_publisher_reputation_score}",
            f"--output_classified_compound={Tables.classified_v2_compounds}",
            f"--output_classifieds_to_delete_table={Tables.classifieds_to_delete}",
            "--overwrite_schema",
        ],
    ),
    create_task(
        entry_point="plugins_classifieds_publisher",
        parameters=[
            f"--input_classifieds_table={Tables.classified_v2_compounds}",
            f"--input_classifieds_to_delete_table={Tables.classifieds_to_delete}",
            f"--output_published_listings_table={Tables.classified_published_listings}",
            f"--logging_table={Tables.classified_logging_table}",
            f"--deployment_env={ENV}",
            "--running_mode=prod",
            "--overwrite_schema",
        ],
    ),
]

join_plugins = DummyOperator(task_id="join_plugins", dag=dag)

execute_job_cluster_task >> join_plugins

join_plugins >> plugin_tasks
join_plugins >> classifieds_tasks[0]
chain(*classifieds_tasks)
join_plugins >> zordominium_tasks[0]
chain(*zordominium_tasks)

classifieds_tasks[0] >> classifieds_v2_tasks[0]
zordominium_tasks[0] >> classifieds_v2_tasks[0]
chain(*classifieds_v2_tasks)
