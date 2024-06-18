import os
from datetime import datetime, timedelta
from typing import List

import pendulum
from airflow.models import DAG
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

# from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.services.configuration_service import ConfigurationService

VESPUCIO_PACKAGE_NAME = "vespucio"
# TO DO: Add the package version in the config file
# When updating the vespucio version here, don't forget to update this in the zordominium_vespucio_plugin dag
VESPUCIO_PACKAGE_VERSION = "0.12.0"
VESPUCIO_WHEEL_FILE = (
    f"{VESPUCIO_PACKAGE_NAME}-{VESPUCIO_PACKAGE_VERSION}-py3-none-any.whl"
)

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

CLUSTER_DESCRIPTION = config_service.get_config("databricks_13_3_med_general_cluster")
DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
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
    databricks_conn_id="databricks_job_cluster",
    dag=dag,
    task_id="execute-job-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
    libraries=LIBRARIES,
)


def create_task(entry_point: str, parameters: List[str], task_id: str = None):
    return QuintoAndarDatabricksCheckJobTaskOperator(
        databricks_conn_id="databricks_job_cluster",
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
    source_ebdb_condo = "vespucio_sources_delta.source_ebdb_condo"
    source_kodak_metadata_condo = "vespucio_sources_delta.source_kodak_metadata_condo"
    source_sindiconet_condo = "vespucio_sources_delta.source_sindiconet_condo"
    source_ebdb_house = "vespucio_sources_delta.source_ebdb_house"
    source_navent_houses = "vespucio_sources_delta.source_navent_houses"
    source_union_houses = "vespucio_sources_delta.source_union_house"
    source_itbi_houses = "vespucio_sources_delta.source_itbi_house"
    source_iptu_houses = "vespucio_sources_delta.source_iptu_house"

    step1_staged_condos = "vespucio_pipeline_delta.step1_staged_condos"
    step1_staged_houses = "vespucio_pipeline_delta.step1_staged_houses"
    step2_geocode_cache = "vespucio_pipeline_delta.step2_geocode_cache"
    step2_geocoded_condos = "vespucio_pipeline_delta.step2_geocoded_condos"
    step2_geocoded_houses = "vespucio_pipeline_delta.step2_geocoded_houses"
    step3_clustered_condos = "vespucio_pipeline_delta.step3_clustered_condos"
    step3_clustered_houses = "vespucio_pipeline_delta.step3_clustered_houses"
    step4_merged_condos = "vespucio_pipeline_delta.step4_merged_condos"
    step4_merged_houses = "vespucio_pipeline_delta.step4_merged_houses"
    step5_images_houses = "vespucio_pipeline_delta.step5_images_houses"
    step6_linked_condos = "vespucio_pipeline_delta.step6_linked_condos"

    condo_compounds = "vespucio_prod_delta.condo_compounds"
    house_compounds = "vespucio_prod_delta.house_compounds"
    listings = "vespucio_prod_delta.listings"

    # golden_set_condo_compounds = (
    #     "vespucio_goldenset_delta.condo_compounds_employee_sample_v1"
    # )
    # golden_set_condo_compounds_diff = (
    #     "vespucio_goldenset_delta.condo_compounds_goldenset_diff"
    # )

    ebdb_clean_house_enrichment = "datalake_ebdb_clean.house_enrichment"


source_tasks = [
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
]

#dbutils = BaseDBUtils().get_dbutils()
#if dbutils is None:
#    raise RuntimeError("DBUtils not found")

kodak_api_key = ""
# @toodo fix dbutils secret loading
# kodak_api_key = dbutils.secrets.get("quintoandar", APIEnum.KODAK)

core_tasks = [
    create_task(
        entry_point="core_step1stage",
        parameters=[
            f"--input_source_ebdb_condos={Tables.source_ebdb_condo}",
            f"--input_source_kodak_metadata_condos={Tables.source_kodak_metadata_condo}",
            f"--input_source_sindiconet_condos={Tables.source_sindiconet_condo}",
            f"--input_source_ebdb_houses={Tables.source_ebdb_house}",
            f"--input_source_navent_houses={Tables.source_navent_houses}",
            f"--input_source_union_houses={Tables.source_union_houses}",
            f"--overwrite_schema",
            f"--output_staged_condos={Tables.step1_staged_condos}",
            f"--output_staged_houses={Tables.step1_staged_houses}",
        ],
    ),
    create_task(
        entry_point="core_step2geocode",
        parameters=[
            f"--enable_online_geocoder",
            f"--geocode_username=vespucio_prod_pipeline",
            f"--google_geocode_api_keys_from_secret={APIEnum.GOOGLE_GEOCODING}",
            f"--geocode_cache_table={Tables.step2_geocode_cache}",
            f"--update_cache",
            f"--input_staged_condos={Tables.step1_staged_condos}",
            f"--input_staged_houses={Tables.step1_staged_houses}",
            f"--overwrite_schema",
            f"--output_geocoded_condos={Tables.step2_geocoded_condos}",
            f"--output_geocoded_houses={Tables.step2_geocoded_houses}",
        ],
    ),
    create_task(
        entry_point="core_step3cluster",
        parameters=[
            f"--input_geocoded_condos={Tables.step2_geocoded_condos}",
            f"--input_geocoded_houses={Tables.step2_geocoded_houses}",
            f"--overwrite_schema",
            f"--output_clustered_condos={Tables.step3_clustered_condos}",
            f"--output_clustered_houses={Tables.step3_clustered_houses}",
        ],
    ),
    create_task(
        entry_point="core_step4merge",
        parameters=[
            f"--input_staged_condos={Tables.step1_staged_condos}",
            f"--input_staged_houses={Tables.step1_staged_houses}",
            f"--input_clustered_condos={Tables.step3_clustered_condos}",
            f"--input_clustered_houses={Tables.step3_clustered_houses}",
            f"--overwrite_schema",
            f"--output_merged_condos={Tables.step4_merged_condos}",
            f"--output_merged_houses={Tables.step4_merged_houses}",
        ],
    ),
    create_task(
        entry_point="core_step5images",
        parameters=[
            f"--input_merged_houses={Tables.step4_merged_houses}",
            f"--input_images_houses={Tables.step5_images_houses}",
            "--overwrite_schema",
            f"--output_images_houses={Tables.step5_images_houses}",
            f"--kodak_auth_token={kodak_api_key}",
            "--kodak_api_url=https://kodak.quintoandar.com.br/s2s/v1",
            "--thumbor_photo_url=https://www.quintoandar.com.br/img/v2",
        ],
    )
]

listing_task = create_task(
    entry_point="core_step6listing",
    parameters=[
        f"--input_images_houses={Tables.step5_images_houses}",
        f"--overwrite_schema",
        f"--output_listings={Tables.listings}",
    ],
)

linking_task = create_task(
    entry_point="core_step6link",
    parameters=[
        f"--input_merged_condos={Tables.step4_merged_condos}",
        f"--input_images_houses={Tables.step5_images_houses}",
        f"--overwrite_schema",
        f"--output_linked_condos={Tables.step6_linked_condos}",
        f"--output_house_compounds={Tables.house_compounds}",
    ],
)

condo_plans_task = create_task(
    entry_point="core_step7condo_plans",
    parameters=[
        f"--input_linked_condos={Tables.step6_linked_condos}",
        f"--input_house_compounds={Tables.house_compounds}",
        "--overwrite_schema",
        f"--output_condo_compounds={Tables.condo_compounds}",
    ],
)

yesterday = "{{ ds }}"
today = "{{ macros.ds_add(ds, 1)  }}"

plugin_tasks = [
    create_task(
        entry_point="plugins_compound_indexer",
        parameters=[
            f"--elasticsearch_url=https://vpc-vespucio-prod-us-east-1-o56l6pbmnwaphvb7rqxzsapso4.us-east-1.es.amazonaws.com/",
            f"--update_alias",
            f"--delete_old_indices",
            f"--input_condo_compounds={Tables.condo_compounds}",
            f"--input_house_compounds={Tables.house_compounds}",
            f"--input_geocode_cache={Tables.step2_geocode_cache}",
            f"--output_index_prefix=vespucio_prod",
        ],
    ),
    create_task(
        entry_point="plugins_rede_house_enrichment_consolidate",
        parameters=[
            f"--sqs_queue_url=https://sqs.us-east-1.amazonaws.com/632540934959/ProdMainHouseEnrichmentHousesToBeReEnriched",
            f"--sqs_region=us-east-1",
            f"--sqs_batch_size=10",
            f"--sqs_num_writers=10",
            f"--input_ebdb_house_enrichment={Tables.ebdb_clean_house_enrichment}",
            f"--input_condo_compounds={Tables.condo_compounds}",
            f"--input_house_compounds={Tables.house_compounds}",
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

execute_job_cluster_task >> source_tasks
core_tasks[0] << source_tasks
chain(*core_tasks)
core_tasks[-1] >> listing_task
core_tasks[-1] >> linking_task
linking_task >> condo_plans_task >> plugin_tasks
