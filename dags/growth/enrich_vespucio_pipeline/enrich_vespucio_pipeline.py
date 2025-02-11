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
from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.databricks.cluster_permission_enum import ClusterPermissionEnum
from bietlejuice.base.databricks.databricks_group_name_enum import (
    DatabricksGroupNameEnum,
)

from bietlejuice.services.configuration_service import ConfigurationService

VESPUCIO_PACKAGE_NAME = "vespucio"
LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2021, 8, 24, 0, 0, 0, tzinfo=LOCAL_TZ)

CONTEXT = "vespucio_pipeline"
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
CLUSTER_DESCRIPTION["spark_conf"]["spark.databricks.sql.initial.catalog.namespace"] = "quintoandar_{{ var.value.environment }}"

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
LIBRARIES = [{"whl": f"{artifacts_bucket}/vespucio/{VESPUCIO_WHEEL_FILE}"}]
DAG_DOCUMENTATION = config_service.get_config("dag_documentation")
DAG_OWNER = DAGOwnerEnum.DATA_GROWTH

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
    databricks_conn_id="databricks_new",
    dag=dag,
    task_id="execute-job-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=LIBRARIES,
)


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


class Tables:
    source_clustering_image_model = (
        "vespucio_sources_delta.source_clustering_image_model"
    )
    source_ebdb_condo = "vespucio_sources_delta.source_ebdb_condo"
    source_kodak_metadata_condo = "vespucio_sources_delta.source_kodak_metadata_condo"
    source_navent_condo = "vespucio_sources_delta.source_navent_condo"
    source_sindiconet_condo = "vespucio_sources_delta.source_sindiconet_condo"
    source_union_condo = "vespucio_sources_delta.source_union_condo"
    source_iptu_condo = "vespucio_sources_delta.source_iptu_condo"
    source_ebdb_house = "vespucio_sources_delta.source_ebdb_house"
    """
    Instead of using `vespucio_sources_delta.source_navent_houses` we must use `_composed` version, which is
    recreated every pipeline run with the increase of blocklist statuses
    """
    source_navent_houses_composed = (
        "vespucio_sources_delta.source_navent_houses_composed"
    )
    source_union_houses = "vespucio_sources_delta.source_union_house"
    source_itbi_houses = "vespucio_sources_delta.source_itbi_house"
    source_iptu_houses = "vespucio_sources_delta.source_iptu_house"
    source_cnefe_houses = "vespucio_sources_delta.source_cnefe_house"
    source_loft_houses = "vespucio_sources_delta.source_loft_house"
    source_viva_real_houses = "vespucio_sources_delta.source_viva_real_house"
    source_zap_imoveis_houses = "vespucio_sources_delta.source_zap_imoveis_house"

    direct_matches_clustering_image = "vespucio_pipeline_delta.direct_matches_clustering_image"
    indirect_matches_clustering_image = "vespucio_pipeline_delta.indirect_matches_clustering_image"

    stage_step_condos = "vespucio_pipeline_delta.stage_step_condos"
    stage_step_houses = "vespucio_pipeline_delta.stage_step_houses"
    geocode_step_cache = "vespucio_pipeline_delta.geocode_step_cache"
    geocode_step_condos = "vespucio_pipeline_delta.geocode_step_condos"
    geocode_step_houses = "vespucio_pipeline_delta.geocode_step_houses"
    address_adjusted_step_condos = (
        "vespucio_pipeline_delta.address_adjusted_step_condos"
    )
    address_adjusted_step_houses = (
        "vespucio_pipeline_delta.address_adjusted_step_houses"
    )
    cluster_step_condos = "vespucio_pipeline_delta.cluster_step_condos"
    cluster_step_houses = "vespucio_pipeline_delta.cluster_step_houses"
    source_predict_step_houses = "vespucio_pipeline_delta.source_predict_step_houses"
    merge_step_condos = "vespucio_pipeline_delta.merge_step_condos"
    merge_step_houses = "vespucio_pipeline_delta.merge_step_houses"
    images_step_houses = "vespucio_pipeline_delta.images_step_houses"
    link_step_condos = "vespucio_pipeline_delta.link_step_condos"
    link_step_houses = "vespucio_pipeline_delta.link_step_houses"
    compound_predict_step_houses = (
        "vespucio_pipeline_delta.compound_predict_step_houses"
    )
    condo_compounds = "vespucio_prod_delta.condo_compounds"
    house_compounds = "vespucio_prod_delta.house_compounds"
    listings = "vespucio_prod_delta.listings"

    zordominium_compounds = "zordominium_vespucio_plugin.zordominium_official_condos"
    classified_compounds = "vespucio_classifieds.classifieds_compound"

    # golden_set_condo_compounds = (
    #     "vespucio_goldenset_delta.condo_compounds_employee_sample_v1"
    # )
    # golden_set_condo_compounds_diff = (
    #     "vespucio_goldenset_delta.condo_compounds_goldenset_diff"
    # )

    kodak_photo = "datalake_kodak_clean.photo"
    kodak_photo_invalid_source = "datalake_kodak_clean.photo_invalid_source"

    ebdb_clean_house_enrichment = "datalake_ebdb_clean.house_enrichment"
    ebdb_clean_house = "datalake_ebdb_clean.house"
    ebdb_clean_region = "datalake_ebdb_clean.region"
    ebdb_clean_map_region = "datalake_ebdb_clean.map_region"


source_tasks = [
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            f"--script=clustering_image_model.sql",
            f"--output_table={Tables.source_clustering_image_model}",
        ],
        task_id="clustering_image_model",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            f"--script=ebdb_condo.sql",
            f"--output_table={Tables.source_ebdb_condo}",
        ],
        task_id="ebdb_condo",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            f"--script=navent_condo.sql",
            f"--output_table={Tables.source_navent_condo}",
        ],
        task_id="navent_condo",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            f"--script=kodak_metadata_condo.sql",
            f"--output_table={Tables.source_kodak_metadata_condo}",
        ],
        task_id="kodak_metadata_condo",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            f"--script=sindiconet_condo.sql",
            f"--output_table={Tables.source_sindiconet_condo}",
        ],
        task_id="sindiconet_condo",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            f"--script=union_condo.sql",
            f"--output_table={Tables.source_union_condo}",
        ],
        task_id="union_condo",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            f"--script=iptu_condo.sql",
            f"--output_table={Tables.source_iptu_condo}",
        ],
        task_id="iptu_condo",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            f"--script=ebdb_house.sql",
            f"--output_table={Tables.source_ebdb_house}",
        ],
        task_id="ebdb_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            f"--script=union_house.sql",
            f"--output_table={Tables.source_union_houses}",
        ],
        task_id="union_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            f"--script=itbi_house.sql",
            f"--output_table={Tables.source_itbi_houses}",
        ],
        task_id="itbi_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            f"--script=iptu_house.sql",
            f"--output_table={Tables.source_iptu_houses}",
        ],
        task_id="iptu_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            f"--script=cnefe_house.sql",
            f"--output_table={Tables.source_cnefe_houses}",
        ],
        task_id="cnefe_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            f"--script=loft_house.sql",
            f"--output_table={Tables.source_loft_houses}",
        ],
        task_id="loft_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            f"--script=viva_real_house.sql",
            f"--output_table={Tables.source_viva_real_houses}",
        ],
        task_id="vivareal_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            f"--script=zap_imoveis_house.sql",
            f"--output_table={Tables.source_zap_imoveis_houses}",
        ],
        task_id="zap_house",
    ),
    create_task(
        entry_point="sources_sql_job",
        parameters=[
            f"--script=navent_house_composed.sql",
            f"--output_table={Tables.source_navent_houses_composed}",
        ],
        task_id="navent_house_composed",
    ),
]

core_matchmaker_tasks = [
    create_task(
        entry_point="core_direct_matches_clustering_image_step",
        parameters=[
            f"--input_source_clustering_image_model={Tables.source_clustering_image_model}",
            f"--overwrite_schema",
            f"--output_direct_matches_clustering_image={Tables.direct_matches_clustering_image}",
        ]
    ),
    create_task(
        entry_point="core_indirect_matches_clustering_image_step",
        parameters=[
            f"--input_source_clustering_image_model={Tables.source_clustering_image_model}",
            f"--input_direct_matches_clustering_image={Tables.direct_matches_clustering_image}",
            f"--overwrite_schema",
            f"--output_indirect_matches_clustering_image={Tables.indirect_matches_clustering_image}",
        ]
    ),
]

core_tasks = [
    create_task(
        entry_point="core_stage_step",
        parameters=[
            f"--input_source_ebdb_condos={Tables.source_ebdb_condo}",
            f"--input_source_navent_condos={Tables.source_navent_condo}",
            f"--input_source_kodak_metadata_condos={Tables.source_kodak_metadata_condo}",
            f"--input_source_sindiconet_condos={Tables.source_sindiconet_condo}",
            f"--input_source_ebdb_houses={Tables.source_ebdb_house}",
            f"--input_source_navent_houses_composed={Tables.source_navent_houses_composed}",
            f"--input_source_union_houses={Tables.source_union_houses}",
            f"--overwrite_schema",
            f"--output_staged_condos={Tables.stage_step_condos}",
            f"--output_staged_houses={Tables.stage_step_houses}",
        ],
    ),
    create_task(
        entry_point="core_geocode_step",
        parameters=[
            f"--enable_online_geocoder",
            f"--geocode_username=vespucio_prod_pipeline",
            f"--google_geocode_api_keys_from_secret={APIEnum.GOOGLE_GEOCODING}",
            f"--geocode_cache_table={Tables.geocode_step_cache}",
            f"--update_cache",
            f"--input_staged_condos={Tables.stage_step_condos}",
            f"--input_staged_houses={Tables.stage_step_houses}",
            f"--overwrite_schema",
            f"--output_geocoded_condos={Tables.geocode_step_condos}",
            f"--output_geocoded_houses={Tables.geocode_step_houses}",
        ],
    ),
    create_task(
        entry_point="core_address_adjustments_step",
        parameters=[
            f"--input_geocoded_condos={Tables.geocode_step_condos}",
            f"--input_geocoded_houses={Tables.geocode_step_houses}",
            f"--input_source_cnefe_houses={Tables.source_cnefe_houses}",
            f"--overwrite_schema",
            f"--output_address_adjusted_condos={Tables.address_adjusted_step_condos}",
            f"--output_address_adjusted_houses={Tables.address_adjusted_step_houses}",
        ],
    ),
    create_task(
        entry_point="core_cluster_step",
        parameters=[
            f"--input_address_adjusted_condos={Tables.address_adjusted_step_condos}",
            f"--input_address_adjusted_houses={Tables.address_adjusted_step_houses}",
            f"--overwrite_schema",
            f"--output_clustered_condos={Tables.cluster_step_condos}",
            f"--output_clustered_houses={Tables.cluster_step_houses}",
        ],
    ),
    create_task(
        entry_point="core_source_predict_step",
        parameters=[
            f"--input_staged_houses={Tables.stage_step_houses}",
            f"--input_clustered_houses={Tables.cluster_step_houses}",
            f"--overwrite_schema",
            f"--output_source_predicted_houses={Tables.source_predict_step_houses}",
        ],
    ),
    create_task(
        entry_point="core_merge_step",
        parameters=[
            f"--input_staged_condos={Tables.stage_step_condos}",
            f"--input_staged_houses={Tables.stage_step_houses}",
            f"--input_clustered_condos={Tables.cluster_step_condos}",
            f"--input_clustered_houses={Tables.cluster_step_houses}",
            f"--input_source_predicted_houses={Tables.source_predict_step_houses}",
            f"--overwrite_schema",
            f"--output_merged_condos={Tables.merge_step_condos}",
            f"--output_merged_houses={Tables.merge_step_houses}",
        ],
    ),
]

images_and_relations_tasks = [
    create_task(
        entry_point="core_images_step",
        parameters=[
            f"--input_merged_houses={Tables.merge_step_houses}",
            f"--input_kodak_photo_invalid_source={Tables.kodak_photo_invalid_source}",
            f"--input_kodak_photo={Tables.kodak_photo}",
            "--overwrite_schema",
            f"--output_images_houses={Tables.images_step_houses}",
            f"--configcat_sdk_key_path={APIEnum.VESPUCIO_CONFIGCAT_SDK_KEY_PATH}",
            f"--kodak_photo_sns_arn={config_service.get_config('kodak_photo_sns_arn')}",
            "--kodak_photo_sns_region=us-east-1",
            "--thumbor_photo_url=https://www.quintoandar.com.br/img/v2",
        ],
    ),
    create_task(
        entry_point="core_link_step",
        parameters=[
            f"--input_merged_condos={Tables.merge_step_condos}",
            f"--input_merged_houses={Tables.merge_step_houses}",
            f"--overwrite_schema",
            f"--output_linked_condos={Tables.link_step_condos}",
            f"--output_linked_houses={Tables.link_step_houses}",
        ],
    ),
]

predict_and_join_task = [
    create_task(
        entry_point="core_compound_predict_step",
        parameters=[
            f"--input_linked_condos={Tables.link_step_condos}",
            f"--input_linked_houses={Tables.link_step_houses}",
            f"--overwrite_schema",
            f"--output_compound_predicted_houses={Tables.compound_predict_step_houses}",
        ],
    ),
    create_task(
        entry_point="core_join_compound_step",
        parameters=[
            f"--input_images_houses={Tables.images_step_houses}",
            f"--input_linked_houses={Tables.link_step_houses}",
            f"--input_compound_predicted_houses={Tables.compound_predict_step_houses}",
            f"--overwrite_schema",
            f"--output_house_compounds={Tables.house_compounds}",
        ],
    ),
]

after_join_tasks = [
    create_task(
        entry_point="core_listing_step",
        parameters=[
            f"--input_house_compounds={Tables.house_compounds}",
            f"--input_linked_condos={Tables.link_step_condos}",
            f"--overwrite_schema",
            f"--output_listings_houses={Tables.listings}",
        ],
    ),
    create_task(
        entry_point="core_condo_plans_step",
        parameters=[
            f"--input_linked_condos={Tables.link_step_condos}",
            f"--input_house_compounds={Tables.house_compounds}",
            "--overwrite_schema",
            f"--output_condo_compounds={Tables.condo_compounds}",
        ],
    ),
]


yesterday = "{{ ds }}"
today = "{{ macros.ds_add(ds, 1)  }}"

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
        ],
    ),
    create_task(
        entry_point="plugins_listing_indexer",
        parameters=[
            f"--elasticsearch_url={config_service.get_config('elastic_search_url')}",
            f"--update_alias",
            f"--delete_old_indices",
            f"--input_listings={Tables.listings}",
            f"--output_index_prefix=vespucio_prod",
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
            f"--redis_host=redis.pwa-tenants-link-service.quintoandar.com.br",
            f"--redis_port=6379",
        ],
    ),
    # create_task(
    #     entry_point="plugins_diff_tables",
    #     parameters=[
    #         f"--overwrite_schema",
    #         f"--input_left_table={Tables.condo_compounds}@{yesterday}",
    #         f"--input_right_table={Tables.condo_compounds}@{today}",
    #         f"--join_col=dejavuid",
    #         f"--output_stats_table={Tables.condo_compounds}_daily_diff_stats",
    #         f"--output_diff_table={Tables.condo_compounds}_daily_diff",
    #         f"--output_label=condo_compounds_${yesterday}_vs_{today}",
    #         f"--save_mode=append",
    #     ],
    #     task_id="plugins_diff_condo_compounds",
    # ),
    # create_task(
    #     entry_point="plugins_diff_tables",
    #     parameters=[
    #         f"--overwrite_schema",
    #         f"--input_left_table={Tables.house_compounds}@{yesterday}",
    #         f"--input_right_table={Tables.house_compounds}@{today}",
    #         f"--join_col=dejavuid",
    #         f"--output_stats_table={Tables.house_compounds}_daily_diff_stats",
    #         f"--output_diff_table={Tables.house_compounds}_daily_diff",
    #         f"--output_label=house_compounds_${yesterday}_vs_{today}",
    #         f"--save_mode=append",
    #     ],
    #     task_id="plugins_diff_house_compounds",
    # ),
    # create_task(
    #     entry_point="plugins_diff_tables",
    #     parameters=[
    #         f"--overwrite_schema",
    #         f"--input_left_table={Tables.golden_set_condo_compounds}@{today}",
    #         f"--input_right_table={Tables.condo_compounds}@{today}",
    #         f"--join_col=dejavuid",
    #         f"--ignore_cols=sources,relations,content_md5",
    #         f"--output_stats_table={Tables.golden_set_condo_compounds_diff}_stats",
    #         f"--output_diff_table={Tables.golden_set_condo_compounds_diff}",
    #         f"--output_label=condo_compounds_employee_sample_v1_vs_{today}",
    #         f"--save_mode=append",
    #     ],
    #     task_id="plugins_diff_golden_set_condo_compounds",
    # ),
]


classifieds_tasks = [
    create_task(
        entry_point="plugins_classifieds",
        parameters=[
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
        ],
    ),
]

join_plugins = DummyOperator(task_id="join_plugins", dag=dag)

execute_job_cluster_task >> source_tasks

source_tasks[0] >> core_matchmaker_tasks[0]
chain(*core_matchmaker_tasks)

source_tasks >> core_tasks[0]
chain(*core_tasks)

core_tasks[-1] >> images_and_relations_tasks
images_and_relations_tasks >> predict_and_join_task[0]
chain(*predict_and_join_task)

predict_and_join_task[-1] >> after_join_tasks
after_join_tasks >> join_plugins >> plugin_tasks
join_plugins >> classifieds_tasks[0]
chain(*classifieds_tasks)
