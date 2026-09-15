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
from bietlejuice.base.api.api_enum import APIEnum
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

CONTEXT = "vespucio_pipeline"
DAG_NAME = f"enrich_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"

EXECUTION_HOURS_TIMEOUT = 3.0

_GEOCODE_MAX_PARTITIONS = 5
_GEOCODE_MAX_REQUESTS_PER_PARTITION = 15000

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
    {"spark.metrics.namespace": "data_products.enrich_vespucio_pipeline"}
)
CLUSTER_DESCRIPTION["spark_env_vars"]["OUTPUT_LOCATION"] = output_location
CLUSTER_DESCRIPTION["data_security_mode"] = "SINGLE_USER"
CLUSTER_DESCRIPTION["single_user_name"] = "{{ var.value.databricks_single_user_name }}"
CLUSTER_DESCRIPTION["spark_conf"]["spark.databricks.sql.initial.catalog.namespace"] = (
    "quintoandar_{{ var.value.environment }}"
)
CLUSTER_DESCRIPTION["driver_node_type_id"] = "r5a.4xlarge"
CLUSTER_DESCRIPTION["node_type_id"] = "m5a.4xlarge"
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


source_tasks = [
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=clustering_image_model.sql",
            f"--output_table={Tables.source_clustering_image_model}",
        ],
        task_id="clustering_image_model",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=ebdb_condo.sql",
            f"--output_table={Tables.source_ebdb_condo}",
        ],
        task_id="ebdb_condo",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=navent_condo.sql",
            f"--output_table={Tables.source_navent_condo}",
        ],
        task_id="navent_condo",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=kodak_metadata_condo.sql",
            f"--output_table={Tables.source_kodak_metadata_condo}",
        ],
        task_id="kodak_metadata_condo",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=union_condo.sql",
            f"--output_table={Tables.source_union_condo}",
        ],
        task_id="union_condo",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=iptu_condo.sql",
            f"--output_table={Tables.source_iptu_condo}",
        ],
        task_id="iptu_condo",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=ebdb_house.sql",
            f"--output_table={Tables.source_ebdb_house}",
        ],
        task_id="ebdb_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=union_house.sql",
            f"--output_table={Tables.source_union_houses}",
        ],
        task_id="union_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=idactum_house.sql",
            f"--output_table={Tables.source_idactum_houses}",
        ],
        task_id="idactum_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=idactum_transactions.sql",
            f"--output_table={Tables.source_idactum_transactions}",
        ],
        task_id="idactum_transactions",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=itbi_house.sql",
            f"--output_table={Tables.source_itbi_houses}",
        ],
        task_id="itbi_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=iptu_house.sql",
            f"--output_table={Tables.source_iptu_houses}",
        ],
        task_id="iptu_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=cnefe_house.sql",
            f"--output_table={Tables.source_cnefe_houses}",
        ],
        task_id="cnefe_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=loft_house.sql",
            f"--output_table={Tables.source_loft_houses}",
        ],
        task_id="loft_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=viva_real_house.sql",
            f"--output_table={Tables.source_viva_real_houses}",
        ],
        task_id="vivareal_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=zap_imoveis_house.sql",
            f"--output_table={Tables.source_zap_imoveis_houses}",
        ],
        task_id="zap_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=navent_house_composed.sql",
            f"--output_table={Tables.source_navent_houses_composed}",
        ],
        task_id="navent_house_composed",
    ),
]

stage_step_task = create_task(
    entry_point="core_stage_step",
    parameters=[
        f"--input_source_ebdb_condos={Tables.source_ebdb_condo}",
        f"--input_source_navent_condos={Tables.source_navent_condo}",
        f"--input_source_kodak_metadata_condos={Tables.source_kodak_metadata_condo}",
        f"--input_source_ebdb_houses={Tables.source_ebdb_house}",
        f"--input_source_navent_houses_composed={Tables.source_navent_houses_composed}",
        f"--input_source_union_houses={Tables.source_union_houses}",
        f"--input_source_idactum_houses={Tables.source_idactum_houses}",
        f"--input_source_idactum_transactions={Tables.source_idactum_transactions}",
        "--overwrite_schema",
        f"--output_staged_condos={Tables.stage_step_condos}",
        f"--output_staged_houses={Tables.stage_step_houses}",
    ],
)

address_details_hasher_step_task = create_task(
    entry_point="core_address_details_hasher_step",
    parameters=[
        "--overwrite_schema",
        f"--input_staged_houses={Tables.stage_step_houses}",
        f"--output_address_details_hash={Tables.address_details_hash}",
        f"--output_address_details_hasher_link={Tables.address_details_hasher_link}",
    ],
)

source_adapter_step_task = create_task(
    entry_point="core_source_adapter_step",
    parameters=[
        f"--input_staged_condos={Tables.stage_step_condos}",
        f"--input_staged_houses={Tables.stage_step_houses}",
        "--overwrite_schema",
        f"--output_source_condos={Tables.source_adapter_step_condos}",
        f"--output_source_houses={Tables.source_adapter_step_houses}",
    ],
)

extract_step_task = create_task(
    entry_point="core_extract_step",
    parameters=[
        f"--input_source_condos={Tables.source_adapter_step_condos}",
        f"--input_source_houses={Tables.source_adapter_step_houses}",
        f"--input_address_adjusted_condos={Tables.address_adjusted_step_condos}",
        f"--input_address_adjusted_houses={Tables.address_adjusted_step_houses}",
        "--overwrite_schema",
        f"--output_extracted_condos={Tables.extract_step_condos}",
        f"--output_extracted_houses={Tables.extract_step_houses}",
        f"--output_extracted_houses_images={Tables.extract_step_houses_images}",
    ],
)

prioritize_step_task = create_task(
    entry_point="core_prioritize_step",
    parameters=[
        f"--input_clustered_condos={Tables.cluster_step_condos}",
        f"--input_clustered_houses={Tables.cluster_step_houses}",
        f"--input_extracted_condos={Tables.extract_step_condos}",
        f"--input_extracted_houses={Tables.extract_step_houses}",
        "--overwrite_schema",
        f"--output_prioritized_condos={Tables.prioritize_step_condos}",
        f"--output_prioritized_houses={Tables.prioritize_step_houses}",
    ],
)

address_tasks = [
    create_task(
        entry_point="core_geocode_step",
        parameters=[
            "--enable_online_geocoder",
            "--geocode_username=vespucio_prod_pipeline",
            f"--google_geocode_api_keys_from_secret={APIEnum.GOOGLE_GEOCODING}",
            f"--geocode_cache_table={Tables.geocode_step_cache}",
            "--update_cache",
            f"--max_partitions={_GEOCODE_MAX_PARTITIONS}",
            f"--max_requests_per_partition={_GEOCODE_MAX_REQUESTS_PER_PARTITION}",
            f"--input_staged_condos={Tables.stage_step_condos}",
            f"--input_staged_houses={Tables.stage_step_houses}",
            "--overwrite_schema",
            f"--output_geocoded_condos={Tables.geocode_step_condos}",
            f"--output_geocoded_houses={Tables.geocode_step_houses}",
        ],
    ),
    create_task(
        entry_point="core_address_details_parser_join_step",
        parameters=[
            f"--input_address_details_hasher_link={Tables.address_details_hasher_link}",
            f"--input_geocoded_houses={Tables.geocode_step_houses}",
            f"--input_staged_parsed_complements={Tables.staged_parsed_complements}",
            "--overwrite_schema",
            f"--output_address_details_parser_join_houses={Tables.address_details_parser_join_houses}",
        ],
    ),
    create_task(
        entry_point="core_address_adjustments_step",
        parameters=[
            f"--input_geocoded_condos={Tables.geocode_step_condos}",
            f"--input_address_details_parser_join_houses={Tables.address_details_parser_join_houses}",
            f"--input_source_cnefe_houses={Tables.source_cnefe_houses}",
            f"--input_source_iptu_houses={Tables.source_iptu_houses}",
            "--overwrite_schema",
            f"--configcat_sdk_key_path={APIEnum.VESPUCIO_CONFIGCAT_SDK_KEY_PATH}",
            f"--output_address_adjusted_condos={Tables.address_adjusted_step_condos}",
            f"--output_address_adjusted_houses={Tables.address_adjusted_step_houses}",
        ],
    ),
    create_task(
        entry_point="core_direct_matches_clustering_image_step",
        parameters=[
            f"--input_address_adjusted_houses={Tables.address_adjusted_step_houses}",
            f"--input_source_clustering_image_model={Tables.source_clustering_image_model}",
            "--overwrite_schema",
            f"--configcat_sdk_key_path={APIEnum.VESPUCIO_CONFIGCAT_SDK_KEY_PATH}",
            f"--output_address_adjusted_houses={Tables.address_adjusted_step_houses}",
        ],
    ),
    create_task(
        entry_point="core_indirect_matches_clustering_image_step",
        parameters=[
            f"--input_address_adjusted_houses={Tables.address_adjusted_step_houses}",
            f"--input_source_clustering_image_model={Tables.source_clustering_image_model}",
            "--overwrite_schema",
            f"--configcat_sdk_key_path={APIEnum.VESPUCIO_CONFIGCAT_SDK_KEY_PATH}",
            f"--output_address_adjusted_houses={Tables.address_adjusted_step_houses}",
        ],
    ),
]

cluster_task = create_task(
    entry_point="core_cluster_step",
    parameters=[
        f"--input_address_adjusted_condos={Tables.address_adjusted_step_condos}",
        f"--input_indirect_matches_clustering_image={Tables.address_adjusted_step_houses}",
        "--overwrite_schema",
        f"--output_clustered_condos={Tables.cluster_step_condos}",
        f"--output_clustered_houses={Tables.cluster_step_houses}",
    ],
)

source_predict_task = create_task(
    entry_point="core_source_predict_step",
    parameters=[
        f"--input_staged_houses={Tables.stage_step_houses}",
        f"--input_clustered_houses={Tables.cluster_step_houses}",
        f"--input_source_itbi_houses={Tables.source_itbi_houses}",
        "--overwrite_schema",
        f"--output_source_predicted_houses={Tables.source_predict_step_houses}",
    ],
)

link_task = create_task(
    entry_point="core_link_step",
    parameters=[
        f"--input_staged_condos={Tables.stage_step_condos}",
        f"--input_staged_houses={Tables.stage_step_houses}",
        f"--input_clustered_condos={Tables.cluster_step_condos}",
        f"--input_clustered_houses={Tables.cluster_step_houses}",
        "--overwrite_schema",
        f"--output_linked={Tables.link_step}",
    ],
)

images_tasks = [
    create_task(
        entry_point="core_images_step",
        parameters=[
            f"--input_clustered_houses={Tables.cluster_step_houses}",
            f"--input_extracted_houses_images={Tables.extract_step_houses_images}",
            f"--input_kodak_photo={Tables.kodak_photo}",
            "--overwrite_schema",
            f"--output_images_houses={Tables.images_step_houses}",
            "--thumbor_photo_url=https://www.quintoandar.com.br/img/v2",
        ],
    ),
    create_task(
        entry_point="core_images_upsert_io_step",
        parameters=[
            f"--input_kodak_photo={Tables.kodak_photo}",
            f"--input_clustered_houses={Tables.cluster_step_houses}",
            f"--input_extracted_houses_images={Tables.extract_step_houses_images}",
            f"--input_kodak_photo_invalid_source={Tables.kodak_photo_invalid_source}",
            f"--configcat_sdk_key_path={APIEnum.VESPUCIO_CONFIGCAT_SDK_KEY_PATH}",
            f"--kodak_photo_sns_arn={config_service.get_config('kodak_photo_sns_arn')}",
            "--kodak_photo_sns_region=us-east-1",
        ],
    ),
    create_task(
        entry_point="core_images_delete_io_step",
        parameters=[
            f"--input_kodak_photo={Tables.kodak_photo}",
            f"--input_clustered_houses={Tables.cluster_step_houses}",
            f"--input_extracted_houses_images={Tables.extract_step_houses_images}",
            f"--configcat_sdk_key_path={APIEnum.VESPUCIO_CONFIGCAT_SDK_KEY_PATH}",
            f"--kodak_photo_sns_arn={config_service.get_config('kodak_photo_sns_arn')}",
            "--kodak_photo_sns_region=us-east-1",
        ],
    ),
]

join_and_predict_task = [
    create_task(
        entry_point="core_join_compound_step",
        parameters=[
            "--overwrite_schema",
            f"--input_staged_houses={Tables.stage_step_houses}",
            f"--input_staged_condos={Tables.stage_step_condos}",
            f"--input_images_houses={Tables.images_step_houses}",
            f"--input_prioritized_houses={Tables.prioritize_step_houses}",
            f"--input_prioritized_condos={Tables.prioritize_step_condos}",
            f"--input_linked={Tables.link_step}",
            f"--input_joined_condos={Tables.join_step_condos}",
            f"--output_joined_houses={Tables.join_step_houses}",
            f"--output_joined_condos={Tables.join_step_condos}",
        ],
    ),
    create_task(
        entry_point="core_compound_predict_step",
        parameters=[
            "--overwrite_schema",
            f"--input_linked={Tables.link_step}",
            f"--input_joined_houses={Tables.join_step_houses}",
            f"--input_source_predicted_houses={Tables.source_predict_step_houses}",
            f"--configcat_sdk_key_path={APIEnum.VESPUCIO_CONFIGCAT_SDK_KEY_PATH}",
            f"--output_house_compounds={Tables.house_compounds}",
        ],
    ),
]

after_join_tasks = [
    create_task(
        entry_point="core_listing_step",
        parameters=[
            "--overwrite_schema",
            f"--input_house_compounds={Tables.house_compounds}",
            f"--input_joined_condos={Tables.join_step_condos}",
            f"--output_listings_houses={Tables.listings}",
        ],
    ),
    create_task(
        entry_point="core_condo_plans_step",
        parameters=[
            "--overwrite_schema",
            f"--input_joined_condos={Tables.join_step_condos}",
            f"--input_house_compounds={Tables.house_compounds}",
            f"--output_condo_compounds={Tables.condo_compounds}",
        ],
    ),
]

vespucio_core_pipeline_complete_task = DummyOperator(
    task_id="vespucio-core-pipeline-complete",
    dag=dag,
)
DatasetAdder.attach_dataset_to_task(vespucio_core_pipeline_complete_task)


execute_job_cluster_task >> source_tasks

source_tasks >> stage_step_task
stage_step_task >> address_details_hasher_step_task
stage_step_task >> source_adapter_step_task
stage_step_task >> address_tasks[0]
chain(*address_tasks)

source_adapter_step_task >> extract_step_task
address_tasks[-1] >> extract_step_task
address_tasks[-1] >> cluster_task

cluster_task >> images_tasks
cluster_task >> link_task
cluster_task >> source_predict_task
cluster_task >> prioritize_step_task
extract_step_task >> prioritize_step_task
extract_step_task >> images_tasks


prioritize_step_task >> join_and_predict_task[0]
link_task >> join_and_predict_task[0]
images_tasks[0] >> join_and_predict_task[0]
chain(*join_and_predict_task)

source_predict_task >> join_and_predict_task[1]

join_and_predict_task[-1] >> after_join_tasks

after_join_tasks[0] >> vespucio_core_pipeline_complete_task
after_join_tasks[1] >> vespucio_core_pipeline_complete_task
