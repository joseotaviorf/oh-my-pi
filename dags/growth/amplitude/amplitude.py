import os
from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)
from pendulum import timezone

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.services.configuration_service import ConfigurationService

# Pipeline inputs
SOURCE = "amplitude"
DAG_ID = f"bietlejuice.{SOURCE}"
MAIN_START_DATE = datetime(2019, 1, 1, tzinfo=timezone("America/Sao_Paulo"))
MAIN_SCHEDULE_INTERVAL = "30 23 * * *"
CLUSTER_DESCRIPTION = "custom_cluster"

config_service = ConfigurationService(SOURCE)
PARTITION_COLS = config_service.get_config("partition_cols_dag")
INCREMENTAL_PARTITIONS = config_service.get_config("incremental_partitions")
EXTRA_SPARK_CONF = config_service.get_config("spark_conf")
CLEAN_STAGING_BLOCK_TABLES = config_service.get_config("clean_staging_block_tables")

athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")
datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
raw_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
cluster_configuration = config_service.get_config(CLUSTER_DESCRIPTION)
cluster_configuration["spark_conf"].update(EXTRA_SPARK_CONF)
default_libraries = config_service.get_config("default_libraries")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
ENV = os.environ.get("ENVIRONMENT")

dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": DAGOwnerEnum.DATA_GROWTH,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(SOURCE).format(
        chart_url=doc_md_chart_url, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_configuration,
    libraries=default_libraries,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

events_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="events-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "load_amplitude_raw.py",
            "parameters": [ENV, datalake_bucket, SOURCE, "{{ ds }}"],
        }
    },
)

# sync_metastore_raw_events_structure_task = QuintoAndarDatabricksSubmitRunOperator(
#     task_id="sync-hive-metastore-raw-events-structure",
#     dag=dag,
#     json={
#         "spark_python_task": {
#             "python_file": base_spark_jobs_path + "sync_metastore_tables_structure.py",
#             "parameters": [
#                 datalake_bucket,
#                 LayerEnum.RAW.value,
#                 SOURCE,
#                 "--table-name",
#                 "events",
#             ],
#         }
#     },
# )

sync_metastore_raw_events_partitions_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-hive-metastore-raw-events-partitions",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": base_spark_jobs_path + "sync_metastore_tables_partitions.py",
            "parameters": [
                datalake_bucket,
                LayerEnum.RAW.value,
                SOURCE,
                "--table-name",
                "events",
            ],
        }
    },
)

propagate_table_metadata_raw_events_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"propagate-table-metadata-raw-events",
    json={
        "spark_python_task": {
            "python_file": base_spark_jobs_path + "propagate_raw_tables_metadata.py",
            "parameters": [
                LayerEnum.RAW.value,
                MetadataTypeEnum.TAGS.value,
                SOURCE,
                SOURCE,
                "--table-name",
                "events",
            ],
        }
    },
)

events_raw_to_clean_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="events-raw-to-clean",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "load_incremental_clean.py",
            "parameters": [
                "{{ ds }}",
                ENV,
                datalake_bucket,
                "amplitude",
                "events",
                "--partition_by",
            ]
            + INCREMENTAL_PARTITIONS,
        }
    },
)

sync_metastore_clean_events_structure_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-hive-metastore-clean-events-structure",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": base_spark_jobs_path + "sync_metastore_tables_structure.py",
            "parameters": [
                datalake_bucket,
                LayerEnum.CLEAN.value,
                SOURCE,
                "--table-name",
                "events",
            ],
        }
    },
)

sync_metastore_clean_events_partitions_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-hive-metastore-clean-events-partitions",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": base_spark_jobs_path + "sync_metastore_tables_partitions.py",
            "parameters": [
                datalake_bucket,
                LayerEnum.CLEAN.value,
                SOURCE,
                "--table-name",
                "events",
            ],
        }
    },
)

propagate_table_metadata_clean_events_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"propagate-table-metadata-clean-events",
    json={
        "spark_python_task": {
            "python_file": base_spark_jobs_path + "propagate_table_metadata.py",
            "parameters": [
                LayerEnum.CLEAN.value,
                MetadataTypeEnum.LINEAGE.value,
                SOURCE,
                "events",
            ],
        }
    },
)
# 170698_user_merge
user_merge_170698_raw_to_clean_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="170698-user-merge-raw-to-clean",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "load_incremental_clean.py",
            "parameters": [
                "{{ ds }}",
                ENV,
                datalake_bucket,
                "amplitude",
                "170698_user_merge",
                "--partition_by",
            ]
            + INCREMENTAL_PARTITIONS,
        }
    },
)

sync_metastore_clean_170698_user_merge_structure_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-hive-metastore-clean-170698-user-merge-structure",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": base_spark_jobs_path + "sync_metastore_tables_structure.py",
            "parameters": [
                datalake_bucket,
                LayerEnum.CLEAN.value,
                SOURCE,
                "--table-name",
                "170698_user_merge",
            ],
        }
    },
)

sync_metastore_clean_170698_user_merge_partitions_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-hive-metastore-clean-170698-user-merge-partitions",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": base_spark_jobs_path + "sync_metastore_tables_partitions.py",
            "parameters": [
                datalake_bucket,
                LayerEnum.CLEAN.value,
                SOURCE,
                "--table-name",
                "170698_user_merge",
            ],
        }
    },
)

propagate_table_metadata_clean_170698_user_merge_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"propagate-table-metadata-clean-170698-user-merge",
    json={
        "spark_python_task": {
            "python_file": base_spark_jobs_path + "propagate_table_metadata.py",
            "parameters": [
                LayerEnum.CLEAN.value,
                MetadataTypeEnum.LINEAGE.value,
                SOURCE,
                "170698_user_merge",
            ],
        }
    },
)

# 183047_user_merge
user_merge_183047_raw_to_clean_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="183047-user-merge-raw-to-clean",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "load_incremental_clean.py",
            "parameters": [
                "{{ ds }}",
                ENV,
                datalake_bucket,
                "amplitude",
                "183047_user_merge",
                "--partition_by",
            ]
            + INCREMENTAL_PARTITIONS,
        }
    },
)

sync_metastore_clean_183047_user_merge_structure_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-hive-metastore-clean-183047-user-merge-structure",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": base_spark_jobs_path + "sync_metastore_tables_structure.py",
            "parameters": [
                datalake_bucket,
                LayerEnum.CLEAN.value,
                SOURCE,
                "--table-name",
                "183047_user_merge",
            ],
        }
    },
)

sync_metastore_clean_183047_user_merge_partitions_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-hive-metastore-clean-183047-user-merge-partitions",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": base_spark_jobs_path + "sync_metastore_tables_partitions.py",
            "parameters": [
                datalake_bucket,
                LayerEnum.CLEAN.value,
                SOURCE,
                "--table-name",
                "183047_user_merge",
            ],
        }
    },
)

propagate_table_metadata_clean_183047_user_merge_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"propagate-table-metadata-clean-183047-user-merge",
    json={
        "spark_python_task": {
            "python_file": base_spark_jobs_path + "propagate_table_metadata.py",
            "parameters": [
                LayerEnum.CLEAN.value,
                MetadataTypeEnum.LINEAGE.value,
                SOURCE,
                "183047_user_merge",
            ],
        }
    },
)

# 205027_user_merge
user_merge_205027_raw_to_clean_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="205027-user-merge-raw-to-clean",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "load_incremental_clean.py",
            "parameters": [
                "{{ ds }}",
                ENV,
                datalake_bucket,
                "amplitude",
                "205027_user_merge",
                "--partition_by",
            ]
            + INCREMENTAL_PARTITIONS,
        }
    },
)

sync_metastore_clean_205027_user_merge_structure_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-hive-metastore-clean-205027-user-merge-structure",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": base_spark_jobs_path + "sync_metastore_tables_structure.py",
            "parameters": [
                datalake_bucket,
                LayerEnum.CLEAN.value,
                SOURCE,
                "--table-name",
                "205027_user_merge",
            ],
        }
    },
)

sync_metastore_clean_205027_user_merge_partitions_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-hive-metastore-clean-205027-user-merge-partitions",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": base_spark_jobs_path + "sync_metastore_tables_partitions.py",
            "parameters": [
                datalake_bucket,
                LayerEnum.CLEAN.value,
                SOURCE,
                "--table-name",
                "205027_user_merge",
            ],
        }
    },
)

propagate_table_metadata_clean_205027_user_merge_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"propagate-table-metadata-clean-205027-user-merge",
    json={
        "spark_python_task": {
            "python_file": base_spark_jobs_path + "propagate_table_metadata.py",
            "parameters": [
                LayerEnum.CLEAN.value,
                MetadataTypeEnum.LINEAGE.value,
                SOURCE,
                "205027_user_merge",
            ],
        }
    },
)

update_clean_events_daily_partition_athena_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="update-clean-events-daily-partition-athena",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "update_athena_partitions.py",
            "parameters": [
                "{{ ds }}",
                ENV,
                datalake_bucket,
                athena_query_results_bucket,
                "amplitude",
                "events",
                "clean",
            ],
        }
    },
)

create_clean_staging_events_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="create-clean-staging-events",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "load_incremental_clean_staging.py",
            "parameters": [
                "{{ ds }}",
                ENV,
                datalake_bucket,
                "amplitude",
                "events",
                "--partition_by",
            ]
            + PARTITION_COLS
            + INCREMENTAL_PARTITIONS,
        }
    },
)

update_subpartitions_table_clean_staging_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="update-clean-staging-subpartitions-values",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path
            + "update_subpartitions_table_clean_staging.py",
            "parameters": [
                "{{ ds }}",
                ENV,
                datalake_bucket,
                "amplitude",
                "events",
                "--subpartitions",
            ]
            + PARTITION_COLS,
        }
    },
)

create_subpartitioned_tables_clean_staging_spark_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="create-clean-staging-subpartitioned-tables-spark",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path
            + "create_subpartitioned_tables_clean_staging.py",
            "parameters": [
                "{{ ds }}",
                ENV,
                datalake_bucket,
                athena_query_results_bucket,
                "amplitude",
                "events",
                "--spark",
            ],
        }
    },
)

create_subpartitioned_tables_clean_staging_athena_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="create-clean-staging-subpartitioned-tables-athena",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path
            + "create_subpartitioned_tables_clean_staging.py",
            "parameters": [
                "{{ ds }}",
                ENV,
                datalake_bucket,
                athena_query_results_bucket,
                "amplitude",
                "events",
                "--athena",
            ],
        }
    },
)

update_subpartitioned_events_clean_staging_spark_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="update-clean-staging-subpartitioned-tables-spark",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path
            + "update_subpartitioned_events_clean_staging.py",
            "parameters": [
                "{{ ds }}",
                ENV,
                datalake_bucket,
                athena_query_results_bucket,
                "amplitude",
                "--spark",
            ],
        }
    },
)

sync_metastore_clean_staging_tables_structure_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-hive-metastore-clean-staging-tables-structure",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": base_spark_jobs_path + "sync_metastore_tables_structure.py",
            "parameters": [
                datalake_bucket,
                LayerEnum.CLEAN_STAGING.value,
                SOURCE,
                "--all-tables",
            ],
        }
    },
)

# sync_metastore_clean_staging_tables_partitions_task = QuintoAndarDatabricksSubmitRunOperator(
#     task_id="sync-hive-metastore-clean-staging-tables-partitions",
#     dag=dag,
#     json={
#         "spark_python_task": {
#             "python_file": base_spark_jobs_path + "sync_metastore_tables_partitions.py",
#             "parameters": [
#                 datalake_bucket,
#                 LayerEnum.CLEAN_STAGING.value,
#                 SOURCE,
#                 "--all-tables",
#             ],
#         }
#     },
# )

propagate_tables_metadata_clean_staging_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="propagate-tables-metadata-clean-staging",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path
            + "propagate_tables_metadata_clean_staging.py",
            "parameters": ["{{ ds }}"],
        }
    },
)

update_subpartitioned_events_clean_staging_athena_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="update-clean-staging-subpartitioned-tables-athena",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path
            + "update_subpartitioned_events_clean_staging.py",
            "parameters": [
                "{{ ds }}",
                ENV,
                datalake_bucket,
                athena_query_results_bucket,
                "amplitude",
                "--athena",
            ],
        }
    },
)

tables_list = DAGPackagesPathService.list_queries_files_in_composer(
    dag_name=SOURCE, layer="clean"
)
load_subpartitioned_events_clean_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="load-subpartitioned-event-tables-to-clean",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "load_subpartitioned_events_clean.py",
            "parameters": [
                "{{ ds }}",
                ENV,
                datalake_bucket,
                "amplitude",
                "--tables_list",
            ]
            + list(set(tables_list) - set(CLEAN_STAGING_BLOCK_TABLES))
            + ["--partition_by"]
            + INCREMENTAL_PARTITIONS,
        }
    },
)

sync_metastore_clean_subpartitioned_events_tables_structure_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-metastore-clean-subpartitioned-event-tables-structure",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": base_spark_jobs_path + "sync_metastore_tables_structure.py",
            "parameters": [
                datalake_bucket,
                LayerEnum.CLEAN.value,
                SOURCE,
                "--all-tables",
            ],
        }
    },
)

sync_metastore_clean_subpartitioned_events_tables_partitions_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-hive-metastore-clean-subpartitioned-events-tables-partitions",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": base_spark_jobs_path + "sync_metastore_tables_partitions.py",
            "parameters": [
                datalake_bucket,
                LayerEnum.CLEAN.value,
                SOURCE,
                "--all-tables",
            ],
        }
    },
)

propagate_tables_metadata_clean_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="propagate-clean-tables-metadata-task",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "propagate_tables_metadata_clean.py",
            "parameters": ["{{ ds }}"],
        }
    },
)

airflow_helpers.chain(
    create_cluster_task,
    events_to_datalake_raw_task,
    # sync_metastore_raw_events_structure_task,
    sync_metastore_raw_events_partitions_task,
    propagate_table_metadata_raw_events_task,
    terminate_cluster_task,
)

airflow_helpers.chain(
    events_to_datalake_raw_task,
    events_raw_to_clean_task,
    sync_metastore_clean_events_structure_task,
    sync_metastore_clean_events_partitions_task,
    propagate_table_metadata_clean_events_task,
    terminate_cluster_task,
)

# 170698_user_merge
airflow_helpers.chain(
    events_to_datalake_raw_task,
    user_merge_170698_raw_to_clean_task,
    sync_metastore_clean_170698_user_merge_structure_task,
    sync_metastore_clean_170698_user_merge_partitions_task,
    propagate_table_metadata_clean_170698_user_merge_task,
    terminate_cluster_task,
)

# 183047_user_merge
airflow_helpers.chain(
    events_to_datalake_raw_task,
    user_merge_183047_raw_to_clean_task,
    sync_metastore_clean_183047_user_merge_structure_task,
    sync_metastore_clean_183047_user_merge_partitions_task,
    propagate_table_metadata_clean_183047_user_merge_task,
    terminate_cluster_task,
)

# 205027_user_merge
airflow_helpers.chain(
    events_to_datalake_raw_task,
    user_merge_205027_raw_to_clean_task,
    sync_metastore_clean_205027_user_merge_structure_task,
    sync_metastore_clean_205027_user_merge_partitions_task,
    propagate_table_metadata_clean_205027_user_merge_task,
    terminate_cluster_task,
)

airflow_helpers.chain(
    events_raw_to_clean_task,
    update_clean_events_daily_partition_athena_task,
    terminate_cluster_task,
)

airflow_helpers.chain(
    events_raw_to_clean_task,
    [create_clean_staging_events_task, update_subpartitions_table_clean_staging_task],
    create_subpartitioned_tables_clean_staging_spark_task,
    [
        create_subpartitioned_tables_clean_staging_athena_task,
        update_subpartitioned_events_clean_staging_spark_task,
    ],
    terminate_cluster_task,
)

airflow_helpers.chain(
    update_subpartitioned_events_clean_staging_spark_task,
    sync_metastore_clean_staging_tables_structure_task,
    # sync_metastore_clean_staging_tables_partitions_task,
    propagate_tables_metadata_clean_staging_task,
    terminate_cluster_task,
)

airflow_helpers.chain(
    create_subpartitioned_tables_clean_staging_athena_task,
    update_subpartitioned_events_clean_staging_athena_task,
    terminate_cluster_task,
)

airflow_helpers.chain(
    update_subpartitioned_events_clean_staging_spark_task,
    load_subpartitioned_events_clean_task,
    sync_metastore_clean_subpartitioned_events_tables_structure_task,
    sync_metastore_clean_subpartitioned_events_tables_partitions_task,
    propagate_tables_metadata_clean_task,
    terminate_cluster_task,
)
