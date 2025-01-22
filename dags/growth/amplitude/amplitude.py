import os
from datetime import datetime, timedelta

import airflow.utils.helpers as airflow_helpers
from airflow.models import DAG
from airflow.operators.dummy_operator import DummyOperator
from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)
from pendulum import timezone

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.services.configuration_service import ConfigurationService

# Pipeline inputs
SOURCE = "amplitude"
DAG_ID = f"bietlejuice.{SOURCE}"
MAIN_START_DATE = datetime(2019, 1, 1, tzinfo=timezone("America/Sao_Paulo"))
CLUSTER_DESCRIPTION = "custom_cluster"
MAIN_SCHEDULE_INTERVAL = None
EXECUTION_TIMEOUT_HOURS = 3

config_service = ConfigurationService(SOURCE)
PARTITION_COLS = config_service.get_config("partition_cols_dag")
INCREMENTAL_PARTITIONS = config_service.get_config("incremental_partitions")
EXTRA_SPARK_CONF = config_service.get_config("spark_conf")
CLEAN_STAGING_BLOCK_TABLES = config_service.get_config("clean_staging_block_tables")

datalake_bucket = config_service.get_config("datalake_bucket")
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
base_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
raw_spark_jobs_path = f"{databricks_bietlejuice_repo_path}/spark_jobs/{SOURCE}/"
doc_md_chart_url = config_service.get_config("doc_md_chart_url")
artifacts_bucket = config_service.get_config("artifacts_bucket")
cluster_configuration = config_service.get_config(CLUSTER_DESCRIPTION)
cluster_configuration["spark_conf"].update(EXTRA_SPARK_CONF)
cluster_configuration["data_security_mode"] = "SINGLE_USER"
cluster_configuration["single_user_name"] = "{{ var.value.databricks_single_user_name }}"
cluster_configuration["spark_conf"]["spark.databricks.sql.initial.catalog.namespace"] = "quintoandar_{{ var.value.environment }}"


default_libraries = config_service.get_config("default_libraries")

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    }
]
ENV = os.environ.get("ENVIRONMENT")

PROPAGATE_TABLE_METADATA_TASK_PREFIX = "propagate-table-metadata"
PROPAGATION_BYPASS_TASK_PREFIX = "propagation-bypass"
SYNC_HIVE_METASTORE_PARTITIONS_TASK_PREFIX = "sync-hive-metastore-partitions"
SYNC_HIVE_METASTORE_STRUCTURE_TASK_PREFIX = "sync-hive-metastore-structure"

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

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(databricks_conn_id="databricks_new", dag=dag,
    task_id="create-cluster",
    cluster_configuration=cluster_configuration,
    libraries=default_libraries,
    access_control_list=DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(databricks_conn_id="databricks_new", dag=dag, task_id="terminate-cluster"
)

events_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id="events-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "load_amplitude_raw.py",
            "parameters": [ENV, datalake_bucket, SOURCE, "{{ ds }}"],
        }
    },
    execution_timeout=timedelta(hours=EXECUTION_TIMEOUT_HOURS),
)

propagate_table_metadata_raw_events_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", dag=dag,
    task_id=f"propagate-table-metadata-raw-events",
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "propagate_raw_tables_metadata.py",
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

events_raw_to_clean_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id=DatalakeTaskGroup.generate_default_task_id(
        task_prefix=DatalakeTaskGroup.LOAD_TASK_PREFIX,
        layer=LayerEnum.CLEAN,
        schema=SOURCE,
        table_name="events",
    ),
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
    execution_timeout=timedelta(hours=EXECUTION_TIMEOUT_HOURS),
)

sync_metastore_clean_events_structure_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id=DatalakeTaskGroup.generate_default_task_id(
        task_prefix=SYNC_HIVE_METASTORE_STRUCTURE_TASK_PREFIX,
        layer=LayerEnum.CLEAN,
        schema=SOURCE,
        table_name="events",
    ),
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "sync_metastore_tables_structure.py",
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

sync_metastore_clean_events_partitions_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id=DatalakeTaskGroup.generate_default_task_id(
        task_prefix=SYNC_HIVE_METASTORE_PARTITIONS_TASK_PREFIX,
        layer=LayerEnum.CLEAN,
        schema=SOURCE,
        table_name="events",
    ),
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "sync_metastore_tables_partitions.py",
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

propagate_table_metadata_clean_events_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", dag=dag,
    task_id=DatalakeTaskGroup.generate_default_task_id(
        task_prefix=PROPAGATE_TABLE_METADATA_TASK_PREFIX,
        layer=LayerEnum.CLEAN,
        schema=SOURCE,
        table_name="events",
    ),
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "propagate_table_metadata.py",
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
user_merge_170698_raw_to_clean_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id=DatalakeTaskGroup.generate_default_task_id(
        task_prefix=DatalakeTaskGroup.LOAD_TASK_PREFIX,
        layer=LayerEnum.CLEAN,
        schema=SOURCE,
        table_name="170698_user_merge",
    ),
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

sync_metastore_clean_170698_user_merge_structure_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id=DatalakeTaskGroup.generate_default_task_id(
        task_prefix=SYNC_HIVE_METASTORE_STRUCTURE_TASK_PREFIX,
        layer=LayerEnum.CLEAN,
        schema=SOURCE,
        table_name="170698_user_merge",
    ),
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "sync_metastore_tables_structure.py",
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

sync_metastore_clean_170698_user_merge_partitions_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id=DatalakeTaskGroup.generate_default_task_id(
        task_prefix=SYNC_HIVE_METASTORE_PARTITIONS_TASK_PREFIX,
        layer=LayerEnum.CLEAN,
        schema=SOURCE,
        table_name="170698_user_merge",
    ),
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "sync_metastore_tables_partitions.py",
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

propagate_table_metadata_clean_170698_user_merge_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", dag=dag,
    task_id=DatalakeTaskGroup.generate_default_task_id(
        task_prefix=PROPAGATE_TABLE_METADATA_TASK_PREFIX,
        layer=LayerEnum.CLEAN,
        schema=SOURCE,
        table_name="170698_user_merge",
    ),
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "propagate_table_metadata.py",
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
user_merge_183047_raw_to_clean_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id=DatalakeTaskGroup.generate_default_task_id(
        task_prefix=DatalakeTaskGroup.LOAD_TASK_PREFIX,
        layer=LayerEnum.CLEAN,
        schema=SOURCE,
        table_name="183047_user_merge",
    ),
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

sync_metastore_clean_183047_user_merge_structure_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id=DatalakeTaskGroup.generate_default_task_id(
        task_prefix=SYNC_HIVE_METASTORE_STRUCTURE_TASK_PREFIX,
        layer=LayerEnum.CLEAN,
        schema=SOURCE,
        table_name="183047_user_merge",
    ),
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "sync_metastore_tables_structure.py",
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

sync_metastore_clean_183047_user_merge_partitions_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id=DatalakeTaskGroup.generate_default_task_id(
        task_prefix=SYNC_HIVE_METASTORE_PARTITIONS_TASK_PREFIX,
        layer=LayerEnum.CLEAN,
        schema=SOURCE,
        table_name="183047_user_merge",
    ),
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "sync_metastore_tables_partitions.py",
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

propagate_table_metadata_clean_183047_user_merge_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", dag=dag,
    task_id=DatalakeTaskGroup.generate_default_task_id(
        task_prefix=PROPAGATE_TABLE_METADATA_TASK_PREFIX,
        layer=LayerEnum.CLEAN,
        schema=SOURCE,
        table_name="183047_user_merge",
    ),
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "propagate_table_metadata.py",
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
user_merge_205027_raw_to_clean_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id=DatalakeTaskGroup.generate_default_task_id(
        task_prefix=DatalakeTaskGroup.LOAD_TASK_PREFIX,
        layer=LayerEnum.CLEAN,
        schema=SOURCE,
        table_name="205027_user_merge",
    ),
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

sync_metastore_clean_205027_user_merge_structure_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id=DatalakeTaskGroup.generate_default_task_id(
        task_prefix=SYNC_HIVE_METASTORE_STRUCTURE_TASK_PREFIX,
        layer=LayerEnum.CLEAN,
        schema=SOURCE,
        table_name="205027_user_merge",
    ),
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "sync_metastore_tables_structure.py",
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

sync_metastore_clean_205027_user_merge_partitions_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id=DatalakeTaskGroup.generate_default_task_id(
        task_prefix=SYNC_HIVE_METASTORE_PARTITIONS_TASK_PREFIX,
        layer=LayerEnum.CLEAN,
        schema=SOURCE,
        table_name="205027_user_merge",
    ),
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "sync_metastore_tables_partitions.py",
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

propagate_table_metadata_clean_205027_user_merge_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", dag=dag,
    task_id=DatalakeTaskGroup.generate_default_task_id(
        task_prefix=PROPAGATE_TABLE_METADATA_TASK_PREFIX,
        layer=LayerEnum.CLEAN,
        schema=SOURCE,
        table_name="205027_user_merge",
    ),
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "propagate_table_metadata.py",
            "parameters": [
                LayerEnum.CLEAN.value,
                MetadataTypeEnum.LINEAGE.value,
                SOURCE,
                "205027_user_merge",
            ],
        }
    },
)

create_clean_staging_events_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id="create-clean-staging-events",
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

update_subpartitions_table_clean_staging_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id="update-clean-staging-subpartitions-values",
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

create_subpartitioned_tables_clean_staging_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id="create-clean-staging-subpartitioned-tables",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path
            + "create_subpartitioned_tables_clean_staging.py",
            "parameters": ["{{ ds }}", ENV, datalake_bucket, "amplitude", "events"],
        }
    },
)

update_subpartitioned_events_clean_staging_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id="update-clean-staging-subpartitioned-tables",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path
            + "update_subpartitioned_events_clean_staging.py",
            "parameters": ["{{ ds }}", ENV, datalake_bucket, "amplitude"],
        }
    },
)

tables_list = DAGPackagesPathService.list_queries_files_in_composer(
    dag_name=SOURCE, layer="clean"
)
subpartitioned_table_list = list(set(tables_list) - set(CLEAN_STAGING_BLOCK_TABLES))

load_subpartitioned_clean_tables_tasks = []
for table in subpartitioned_table_list:

    load_subpartitioned_clean_table_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id=DatalakeTaskGroup.generate_default_task_id(
            task_prefix=DatalakeTaskGroup.LOAD_TASK_PREFIX,
            layer=LayerEnum.CLEAN,
            schema=SOURCE,
            table_name=table,
        ),
        dag=dag,
        json={
            "spark_python_task": {
                "python_file": raw_spark_jobs_path + "load_subpartitioned_events_clean.py",
                "parameters": [
                    "{{ ds }}",
                    ENV,
                    datalake_bucket,
                    "amplitude",
                    table,
                ]
                + ["--partition_by"]
                + INCREMENTAL_PARTITIONS,
            }
        },
        execution_timeout=timedelta(hours=EXECUTION_TIMEOUT_HOURS),
    )

    load_subpartitioned_clean_tables_tasks.append(load_subpartitioned_clean_table_task)

load_subpartitioned_all_clean_tables_done_tasks = DummyOperator(
    dag=dag,
    task_id="load-subpartitioned-event-tables-to-clean",
)

sync_metastore_clean_subpartitioned_events_tables_structure_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id="sync-metastore-clean-subpartitioned-event-tables-structure",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "sync_metastore_tables_structure.py",
            "parameters": [
                datalake_bucket,
                LayerEnum.CLEAN.value,
                SOURCE,
                "--all-tables",
            ],
        }
    },
)

sync_metastore_clean_subpartitioned_events_tables_partitions_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id="sync-hive-metastore-clean-subpartitioned-events-tables-partitions",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "sync_metastore_tables_partitions.py",
            "parameters": [
                datalake_bucket,
                LayerEnum.CLEAN.value,
                SOURCE,
                "--all-tables",
            ],
        }
    },
)

propagate_tables_metadata_clean_task = QuintoAndarDatabricksSubmitRunOperator(databricks_conn_id="databricks_new", task_id="propagate-clean-tables-metadata-task",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": raw_spark_jobs_path + "propagate_tables_metadata_clean.py",
            "parameters": ["{{ ds }}"],
        }
    },
)

# raw tasks dependencies
airflow_helpers.chain(
    create_cluster_task,
    events_to_datalake_raw_task,
    propagate_table_metadata_raw_events_task,
    terminate_cluster_task,
)

# clean tasks dependencies
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
# clean staging tasks dependencies
airflow_helpers.chain(
    events_raw_to_clean_task,
    [create_clean_staging_events_task, update_subpartitions_table_clean_staging_task],
    create_subpartitioned_tables_clean_staging_task,
    update_subpartitioned_events_clean_staging_task,
    load_subpartitioned_clean_tables_tasks,
    load_subpartitioned_all_clean_tables_done_tasks,
    sync_metastore_clean_subpartitioned_events_tables_structure_task,
    sync_metastore_clean_subpartitioned_events_tables_partitions_task,
    propagate_tables_metadata_clean_task,
    terminate_cluster_task,
)
