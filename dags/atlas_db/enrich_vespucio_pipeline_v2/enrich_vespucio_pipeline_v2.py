import os
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
MAIN_START_DATE = datetime(2026, 7, 14, 0, 0, 0, tzinfo=LOCAL_TZ)

CONTEXT = "vespucio_pipeline_v2"
DAG_NAME = f"enrich_{CONTEXT}"
DAG_ID = f"bietlejuice.{DAG_NAME}"

ENV = os.environ.get("ENVIRONMENT")
EXECUTION_HOURS_TIMEOUT = 3.0
PUBLISH_ARTIFACTS_TIMEOUT_HOURS = 5.0

_GEOCODE_MAX_PARTITIONS = 5
_GEOCODE_MAX_REQUESTS_PER_PARTITION = 1500

config_service = ConfigurationService(DAG_NAME)
artifacts_bucket = config_service.get_config("artifacts_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
output_location = config_service.get_config("vespucio_output_path")
kafka_bootstrap_servers = config_service.get_config("kafka_bootstrap_servers")
kodak_photo_duplication_sqs_queue_url = config_service.get_config(
    "kodak_photo_duplication_sqs_queue_url"
)
kodak_photo_sns_arn = config_service.get_config("kodak_photo_sns_arn")

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


def create_task(
    entry_point: str,
    parameters: List[str],
    task_id: str = None,
    execution_timeout_hours: float = EXECUTION_HOURS_TIMEOUT,
):
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
        execution_timeout=timedelta(hours=execution_timeout_hours),
    )


# v1's registry sources are duplicated here (own _v2 tables) so this DAG runs independently
# of enrich_vespucio_pipeline. address_enrich_step_task below calls the unified geocoder
# directly instead of reusing v1's geocode_step_cache / address_details_hasher_link /
# staged_parsed_complements tables.
source_tasks = [
    create_task(
        entry_point="sources_cnefe_house_job",
        parameters=[
            "--script=cnefe_house.sql",
            f"--output_table={Tables.source_cnefe_houses_v2}",
        ],
        task_id="cnefe_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=v2/ebdb_house.sql",
            f"--output_table={Tables.source_ebdb_houses_v2}",
            "--checkpoint_column=_checkpoint",
        ],
        task_id="ebdb_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=v2/navent_house_composed.sql",
            f"--output_table={Tables.source_navent_houses_composed_v2}",
            "--checkpoint_column=_checkpoint",
        ],
        task_id="navent_house_composed",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=v2/navent_24mx_house_composed.sql",
            f"--output_table={Tables.source_navent_24mx_houses_composed_v2}",
            "--checkpoint_column=_checkpoint",
        ],
        task_id="navent_24mx_house_composed",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=v2/union_house.sql",
            f"--output_table={Tables.source_union_houses_v2}",
            "--checkpoint_column=event_timestamp",
        ],
        task_id="union_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=v2/idactum_house.sql",
            f"--output_table={Tables.source_idactum_houses_v2}",
            "--checkpoint_column=dt_load",
        ],
        task_id="idactum_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=v2/idactum_transactions.sql",
            f"--output_table={Tables.source_idactum_transactions_v2}",
            "--checkpoint_column=dt_load",
        ],
        task_id="idactum_transactions",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=v2/itbi_house.sql",
            f"--output_table={Tables.source_itbi_houses_v2}",
            "--checkpoint_column=ts_load",
        ],
        task_id="itbi_house",
    ),
    create_task(
        entry_point="sources_iptu_house_job",
        parameters=[
            f"--output_table={Tables.source_iptu_houses_v2}",
        ],
        task_id="iptu_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=v2/zap_imoveis_house.sql",
            f"--output_table={Tables.source_zap_imoveis_houses_v2}",
            "--checkpoint_column=ts_updated",
        ],
        task_id="zap_house",
    ),
]

# Raw claim sources for claims_step_task below. These aren't registry sources (no
# HouseAdapter/normalization involved) and don't gate registry_step_task, so they're kept
# out of source_tasks and wired directly to claims_step_task instead.
claims_source_tasks = [
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=v2/ebdb_condo_observations.sql",
            f"--output_table={Tables.source_ebdb_condo_observations_v2}",
            "--checkpoint_column=_checkpoint",
        ],
        task_id="ebdb_condo_observations",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=v2/ebdb_condo_kodak_inference.sql",
            f"--output_table={Tables.source_ebdb_condo_kodak_inference_v2}",
        ],
        task_id="ebdb_condo_kodak_inference",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=v2/ebdb_condo_description_inference.sql",
            f"--output_table={Tables.source_ebdb_condo_description_inference_v2}",
        ],
        task_id="ebdb_condo_description_inference",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=v2/ebdb_house_amenities_kodak_inference.sql",
            f"--output_table={Tables.source_ebdb_house_amenities_kodak_inference_v2}",
        ],
        task_id="ebdb_house_amenities_kodak_inference",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            "--script=v2/ebdb_house_amenities_description_inference.sql",
            f"--output_table={Tables.source_ebdb_house_amenities_description_inference_v2}",
        ],
        task_id="ebdb_house_amenities_description_inference",
    ),
]

claims_step_task = create_task(
    entry_point="core_v2_claims_step",
    parameters=[
        f"--input_source_ebdb_condo_observations={Tables.source_ebdb_condo_observations_v2}",
        f"--input_source_ebdb_condo_kodak_inference={Tables.source_ebdb_condo_kodak_inference_v2}",
        f"--input_source_ebdb_condo_description_inference={Tables.source_ebdb_condo_description_inference_v2}",
        f"--input_source_ebdb_house_amenities_kodak_inference={Tables.source_ebdb_house_amenities_kodak_inference_v2}",
        f"--input_source_ebdb_house_amenities_description_inference={Tables.source_ebdb_house_amenities_description_inference_v2}",
        f"--output_claims={Tables.claims_step_v2}",
    ],
)

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
        f"--input_source_navent_24mx_houses_composed={Tables.source_navent_24mx_houses_composed_v2}",
        f"--input_source_union_houses={Tables.source_union_houses_v2}",
        f"--input_source_zap_imoveis_houses={Tables.source_zap_imoveis_houses_v2}",
        "--overwrite_schema",
        f"--output_registry={Tables.registry_step_v2}",
    ],
)

address_normalization_step_task = create_task(
    entry_point="core_v2_address_normalization_step",
    parameters=[
        f"--input_registry={Tables.registry_step_v2}",
        "--overwrite_schema",
        f"--output_address_normalized={Tables.address_normalization_step_v2}",
    ],
)

general_normalization_step_task = create_task(
    entry_point="core_v2_general_normalization_step",
    parameters=[
        f"--input_registry={Tables.registry_step_v2}",
        "--overwrite_schema",
        f"--output_general_normalized={Tables.general_normalization_step_v2}",
    ],
)

image_normalization_step_task = create_task(
    entry_point="core_v2_image_normalization_step",
    parameters=[
        f"--input_registry={Tables.registry_step_v2}",
        "--overwrite_schema",
        f"--output_image_normalized={Tables.image_normalization_step_v2}",
    ],
)

images_upsert_step_task = create_task(
    entry_point="core_v2_images_upsert_step",
    parameters=[
        f"--input_image_normalized={Tables.image_normalization_step_v2}",
        f"--input_kodak_photo_invalid_source={Tables.kodak_photo_invalid_source}",
        f"--output_images_upsert={Tables.images_upsert_step_v2}",
        f"--configcat_sdk_key_path={APIEnum.VESPUCIO_CONFIGCAT_SDK_KEY_PATH}",
        f"--kodak_photo_sns_arn={kodak_photo_sns_arn}",
        "--kodak_photo_sns_region=us-east-1",
    ],
    task_id="images_upsert",
)

address_enrich_step_task = create_task(
    entry_point="core_v2_address_enrich_step",
    parameters=[
        f"--input_address_normalized={Tables.address_normalization_step_v2}",
        "--geocode_username=vespucio_prod_pipeline",
        f"--google_geocode_api_keys_from_secret={APIEnum.GOOGLE_GEOCODING}",
        f"--max_partitions={_GEOCODE_MAX_PARTITIONS}",
        f"--max_requests_per_partition={_GEOCODE_MAX_REQUESTS_PER_PARTITION}",
        "--overwrite_schema",
        f"--output_enriched={Tables.address_enrich_step_v2}",
    ],
)

kodak_atlas_images_task = create_task(
    entry_point="sources_sql_job",
    parameters=[
        "--script=kodak_atlas_images.sql",
        f"--output_table={Tables.source_kodak_atlas_images_v2}",
        "--checkpoint_column=ts_cdc_transaction",
    ],
    task_id="kodak_atlas_images",
)

# Perceptual hashing is gated by the image_enrich_compute_phash ConfigCat flag
# (fails closed: with the flag off or ConfigCat unreachable, phash/phash_64 stay
# null and no S3 image bytes are fetched; hashes already in the output table are
# still carried forward).
image_enrich_step_task = create_task(
    entry_point="core_v2_image_enrich_step",
    parameters=[
        f"--input_source_kodak_atlas_images={Tables.source_kodak_atlas_images_v2}",
        "--overwrite_schema",
        f"--output_image_enrich={Tables.image_enrich_step_v2}",
        "--thumbor_photo_url=https://www.quintoandar.com.br/img/v2",
        f"--configcat_sdk_key_path={APIEnum.VESPUCIO_CONFIGCAT_SDK_KEY_PATH}",
    ],
)

# Publishes Kodak photo duplication requests (dejavuid -> new external_id) to
# ProdKodakPhotoDuplicationQueue so PhotoDuplicationConsumer can duplicate the photo without
# re-downloading/re-uploading it. Volume per run is capped by the
# photo_duplication_step_max_images_per_run ConfigCat flag, which fails closed (defaults to 0,
# i.e. disabled) if --configcat_sdk_key_path is omitted or ConfigCat is unreachable. Omitting
# --sqs_queue_url additionally runs the step in dry-run mode (Forno has no equivalent queue yet).
photo_duplication_step_task = create_task(
    entry_point="core_v2_photo_duplication_step",
    parameters=[
        f"--input_source_kodak_atlas_images={Tables.source_kodak_atlas_images_v2}",
        f"--input_kodak_photo={Tables.kodak_photo}",
        f"--input_photo_duplication_sent={Tables.kodak_photo_duplication_sent}",
        f"--output_photo_duplication_sent={Tables.kodak_photo_duplication_sent}",
        f"--configcat_sdk_key_path={APIEnum.VESPUCIO_CONFIGCAT_SDK_KEY_PATH}",
        *(
            [f"--sqs_queue_url={kodak_photo_duplication_sqs_queue_url}"]
            if kodak_photo_duplication_sqs_queue_url
            else []
        ),
        "--sqs_region=us-east-1",
        "--sqs_batch_size=10",
    ],
    task_id="photo_duplication",
)

artifacts_step_task = create_task(
    entry_point="core_v2_artifacts_step",
    parameters=[
        f"--input_general_normalized={Tables.general_normalization_step_v2}",
        f"--input_enriched={Tables.address_enrich_step_v2}",
        f"--input_image_enrich={Tables.image_enrich_step_v2}",
        "--overwrite_schema",
        f"--output_artifacts={Tables.artifacts_v2}",
    ],
    task_id="artifacts_step",
)

address_grouping_step_task = create_task(
    entry_point="core_v2_address_grouping_step",
    parameters=[
        f"--input_enriched={Tables.address_enrich_step_v2}",
        f"--input_general_normalized={Tables.general_normalization_step_v2}",
        "--overwrite_schema",
        f"--output_match_anchors={Tables.match_anchors_v2}",
    ],
)

image_grouping_step_task = create_task(
    entry_point="core_v2_image_grouping_step",
    parameters=[
        f"--input_source_clustering_image_model={Tables.source_clustering_image_model}",
        "--overwrite_schema",
        f"--output_match_pairs={Tables.match_pairs_v2}",
    ],
)

# Merges listing-level phash pairs (match_method=phash) into the same match_pairs
# table image_grouping writes to, reading phashes from image_enrich's
# images[].phash_64. Incremental runs are driven by the phash_last_run_at table
# property: until the backfill arms that watermark this task is a hard no-op, so
# it is safe to deploy ahead of the backfill. Runs strictly after
# image_grouping_step_task because both MERGE into match_pairs and concurrent
# Delta writers on the same table would conflict.
# hamming_threshold=0 restricts matching to identical hashes (exact equality
# join); the near-duplicate LSH probe is skipped entirely. Raise the threshold
# later to enable near-duplicate matching once exact matching is validated in
# production.
image_phash_grouping_step_task = create_task(
    entry_point="core_v2_image_phash_grouping_step",
    parameters=[
        f"--input_image_enrich={Tables.image_enrich_step_v2}",
        f"--output_match_pairs={Tables.match_pairs_v2}",
        "--hamming_threshold=0",
    ],
    task_id="image_phash_grouping_step",
)

resolve_groups_step_task = create_task(
    entry_point="core_v2_resolve_groups_step",
    parameters=[
        f"--input_enriched={Tables.address_enrich_step_v2}",
        f"--input_match_anchors={Tables.match_anchors_v2}",
        f"--input_match_pairs={Tables.match_pairs_v2}",
        "--overwrite_schema",
        f"--output_artifact_groups={Tables.artifact_groups}",
        f"--output_group_merges={Tables.group_merges}",
    ],
)

groups_step_task = create_task(
    entry_point="core_v2_groups_step",
    parameters=[
        f"--input_artifacts={Tables.artifacts_v2}",
        f"--input_artifact_groups={Tables.artifact_groups}",
        f"--input_group_merges={Tables.group_merges}",
        f"--output_groups={Tables.groups_step_v2}",
    ],
)

resolve_pin_step_task = create_task(
    entry_point="core_v2_resolve_pin_step",
    parameters=[
        f"--input_artifacts={Tables.artifacts_v2}",
        f"--input_match_anchors={Tables.match_anchors_v2}",
        f"--output_pins={Tables.pins_step_v2}",
    ],
)

condominium_step_task = create_task(
    entry_point="core_v2_condominium_step",
    parameters=[
        f"--input_pins={Tables.pins_step_v2}",
        f"--input_match_anchors={Tables.match_anchors_v2}",
        f"--input_general_normalized={Tables.general_normalization_step_v2}",
        f"--input_claims={Tables.claims_step_v2}",
        f"--output_condominium_pins={Tables.condominium_pins_step_v2}",
        f"--output_condominiums={Tables.condominium_step_v2}",
    ],
)

publish_artifacts_step_task = create_task(
    entry_point="core_v2_publish_artifacts_step",
    parameters=[
        f"--input_artifacts={Tables.artifacts_v2}",
        f"--output_artifacts_publish_checkpoint={Tables.artifacts_publish_checkpoint}",
        f"--bootstrap_servers={kafka_bootstrap_servers}",
        f"--deployment_env={ENV}",
        "--security_protocol=SASL_SSL",
        "--credentials_secret_scope=quintoandar",
        "--credentials_secret_key=VESPUCIO_CONFLUENT_CREDENTIALS",
        "--running_mode=prod",
    ],
    task_id="publish_artifacts",
    execution_timeout_hours=PUBLISH_ARTIFACTS_TIMEOUT_HOURS,
)

publish_resolved_identities_step_task = create_task(
    entry_point="core_v2_publish_resolved_identities_step",
    parameters=[
        f"--input_artifact_groups={Tables.artifact_groups}",
        f"--output_resolved_identities_publish_checkpoint={Tables.resolved_identities_publish_checkpoint}",
        f"--bootstrap_servers={kafka_bootstrap_servers}",
        f"--deployment_env={ENV}",
        "--security_protocol=SASL_SSL",
        "--credentials_secret_scope=quintoandar",
        "--credentials_secret_key=VESPUCIO_CONFLUENT_CREDENTIALS",
        "--running_mode=prod",
    ],
    task_id="publish_resolved_identities",
)

# Assigns classifieds house ids to the Mexico Navent (navent_24mx_houses) artifacts, writing
# them back into the shared vespucio_classifieds.classifieds_house_id table under
# source = "24mx" (ID band 400,000,001-799,999,998). The iwbr band is owned by the
# plugins_classifieds_house_id task in the vespucio_pipeline_plugins DAG; both plugins rewrite
# the whole table, so they must not run concurrently.
classifieds_house_id_24mx_task = create_task(
    entry_point="plugins_classifieds_house_id_24mx",
    parameters=[
        f"--input_artifacts={Tables.artifacts_v2}",
        f"--input_classifieds_house_id={Tables.classifieds_house_id}",
        f"--output_classifieds_house_id={Tables.classifieds_house_id}",
    ],
    task_id="classifieds_house_id_24mx",
)

vespucio_v2_pipeline_complete_task = DummyOperator(
    task_id="vespucio-v2-pipeline-complete",
    dag=dag,
)
DatasetAdder.attach_dataset_to_task(vespucio_v2_pipeline_complete_task)


execute_job_cluster_task >> source_tasks
execute_job_cluster_task >> kodak_atlas_images_task
kodak_atlas_images_task >> photo_duplication_step_task
execute_job_cluster_task >> image_grouping_step_task
execute_job_cluster_task >> claims_source_tasks
claims_source_tasks >> claims_step_task
claims_step_task >> vespucio_v2_pipeline_complete_task
source_tasks >> registry_step_task
registry_step_task >> address_normalization_step_task
registry_step_task >> general_normalization_step_task
registry_step_task >> image_normalization_step_task
address_normalization_step_task >> address_enrich_step_task
image_normalization_step_task >> images_upsert_step_task
kodak_atlas_images_task >> image_enrich_step_task
[
    address_enrich_step_task,
    general_normalization_step_task,
] >> address_grouping_step_task
[
    general_normalization_step_task,
    address_enrich_step_task,
    image_enrich_step_task,
] >> artifacts_step_task
[
    image_enrich_step_task,
    image_grouping_step_task,
] >> image_phash_grouping_step_task
[
    address_grouping_step_task,
    image_phash_grouping_step_task,
] >> resolve_groups_step_task
[
    resolve_groups_step_task,
    artifacts_step_task,
] >> groups_step_task
groups_step_task >> vespucio_v2_pipeline_complete_task
artifacts_step_task >> vespucio_v2_pipeline_complete_task
artifacts_step_task >> publish_artifacts_step_task
[
    artifacts_step_task,
    address_grouping_step_task,
] >> resolve_pin_step_task
[
    resolve_pin_step_task,
    address_grouping_step_task,
    general_normalization_step_task,
    claims_step_task,
] >> condominium_step_task
condominium_step_task >> vespucio_v2_pipeline_complete_task
[
    resolve_groups_step_task,
    publish_artifacts_step_task,
] >> publish_resolved_identities_step_task
artifacts_step_task >> classifieds_house_id_24mx_task
classifieds_house_id_24mx_task >> vespucio_v2_pipeline_complete_task
