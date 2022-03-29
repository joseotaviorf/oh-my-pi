from datetime import datetime
import pendulum
import airflow.utils.helpers as airflow_helpers
import os

from airflow.models import DAG
from airflow.models import Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
)
from airflow.operators.quintoandar_dag_logger import QuintoAndarSuccessLoggerOperator

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.base.pipeline.metadata_type_enum import MetadataTypeEnum

DAG_NAME = "amplitude"
DAG_ID = f"bietlejuice.{DAG_NAME}"

ENV = os.environ.get("ENVIRONMENT")
DATALAKE_BUCKET = Variable.get("datalake_bucket")

local_tz = pendulum.timezone("America/Sao_Paulo")
MAIN_START_DATE = datetime(2019, 1, 1, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "30 23 * * *"
DOC_MD_BASE_URL = Variable.get("DOC_MD_BASE_URL")

ATHENA_QUERY_RESULT_LOCATION = Variable.get("athena_query_result_location")
DEFAULT_PARTITION_BY = ["year", "month", "day"]

# s3 paths setup
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
AMPLITUDE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/amplitude/"
BASE_SPARK_JOBS_PATH = f"{S3_PREFIX}/spark_jobs/base/"

LOAD_EVENTS_INTO_DATALAKE_RAW_FILE_PATH = (
    AMPLITUDE_SPARK_JOBS_PATH + "load_events_into_datalake_raw.py"
)
EVENTS_RAW_TO_CLEAN_FILE_PATH = (
    AMPLITUDE_SPARK_JOBS_PATH + "create_clean_incremental_table_in_datalake.py"
)
UPDATE_ATHENA_TABLE_DAILY_PARTITION_FILE_PATH = (
    AMPLITUDE_SPARK_JOBS_PATH + "update_athena_table_daily_partition.py"
)
CREATE_CLEAN_STAGING_EVENTS_FILE_PATH = (
    AMPLITUDE_SPARK_JOBS_PATH + "create_clean_staging_table.py"
)
CREATE_CLEAN_STAGING_SUBPARTITIONED_TABLES_FILE_PATH = (
    AMPLITUDE_SPARK_JOBS_PATH + "create_clean_staging_subpartitioned_tables.py"
)
UPDATE_CLEAN_STAGING_SUBPARTITIONS_VALUES_FILE_PATH = (
    AMPLITUDE_SPARK_JOBS_PATH + "update_clean_staging_table_subpartitions_values.py"
)
UPDATE_CLEAN_STAGING_SUBPARTITIONED_TABLES_FILE_PATH = (
    AMPLITUDE_SPARK_JOBS_PATH + "update_clean_staging_subpartitioned_tables.py"
)
PROPAGATE_TABLES_METADATA_CLEAN_STAGING_FILE_PATH = (
    AMPLITUDE_SPARK_JOBS_PATH + "propagate_tables_metadata_clean_staging.py"
)
# LOAD_SUBPARTITIONED_EVENT_TABLES_TO_CLEAN_FILE_PATH = (
#     AMPLITUDE_SPARK_JOBS_PATH + "load_subpartitioned_event_tables_to_clean.py"
# )
# PROPAGATE_CLEAN_TABLES_METADATA_FILE_PATH = (
#     AMPLITUDE_SPARK_JOBS_PATH + "propagate_clean_tables_metadata.py"
# )

LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)

# cluster configuration
CLUSTER_DESCRIPTION = Variable.get(
    "databricks_memory_optimized_cluster", deserialize_json=True
)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH

# Dag definition
dag = DAG(
    dag_id=DAG_ID,
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME).format(
        chart_url=DOC_MD_BASE_URL, dag_id=DAG_ID
    ),
)

create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag, task_id="create-cluster", cluster_configuration=CLUSTER_DESCRIPTION
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)

events_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="events-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": LOAD_EVENTS_INTO_DATALAKE_RAW_FILE_PATH,
            "parameters": ["{{ ds }}", ENV, DATALAKE_BUCKET],
        }
    },
)

sync_metastore_raw_events_structure_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-hive-metastore-raw-events-structure",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": BASE_SPARK_JOBS_PATH + "sync_metastore_tables_structure.py",
            "parameters": [
                DATALAKE_BUCKET,
                LayerEnum.RAW.value,
                DAG_NAME,
                "--table-name",
                "events",
            ],
        }
    },
)

sync_metastore_raw_events_partitions_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-hive-metastore-raw-events-partitions",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": BASE_SPARK_JOBS_PATH + "sync_metastore_tables_partitions.py",
            "parameters": [
                DATALAKE_BUCKET,
                LayerEnum.RAW.value,
                DAG_NAME,
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
            "python_file": BASE_SPARK_JOBS_PATH + "propagate_raw_tables_metadata.py",
            "parameters": [
                LayerEnum.RAW.value,
                MetadataTypeEnum.TAGS.value,
                DAG_NAME,
                DAG_NAME,
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
            "python_file": EVENTS_RAW_TO_CLEAN_FILE_PATH,
            "parameters": [
                "{{ ds }}",
                ENV,
                DATALAKE_BUCKET,
                "amplitude",
                "events",
                "--partition_by",
            ]
            + DEFAULT_PARTITION_BY,
        }
    },
)

sync_metastore_clean_events_structure_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-hive-metastore-clean-events-structure",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": BASE_SPARK_JOBS_PATH + "sync_metastore_tables_structure.py",
            "parameters": [
                DATALAKE_BUCKET,
                LayerEnum.CLEAN.value,
                DAG_NAME,
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
            "python_file": BASE_SPARK_JOBS_PATH + "sync_metastore_tables_partitions.py",
            "parameters": [
                DATALAKE_BUCKET,
                LayerEnum.CLEAN.value,
                DAG_NAME,
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
            "python_file": BASE_SPARK_JOBS_PATH + "propagate_table_metadata.py",
            "parameters": [
                LayerEnum.CLEAN.value,
                MetadataTypeEnum.LINEAGE.value,
                DAG_NAME,
                "events",
            ],
        }
    },
)

user_merge_raw_to_clean_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="user-merge-raw-to-clean",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": EVENTS_RAW_TO_CLEAN_FILE_PATH,
            "parameters": [
                "{{ ds }}",
                ENV,
                DATALAKE_BUCKET,
                "amplitude",
                "170698_user_merge",
                "--partition_by",
            ]
            + DEFAULT_PARTITION_BY,
        }
    },
)

sync_metastore_clean_user_merge_structure_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-hive-metastore-clean-user-merge-structure",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": BASE_SPARK_JOBS_PATH + "sync_metastore_tables_structure.py",
            "parameters": [
                DATALAKE_BUCKET,
                LayerEnum.CLEAN.value,
                DAG_NAME,
                "--table-name",
                "170698_user_merge",
            ],
        }
    },
)

sync_metastore_clean_user_merge_partitions_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-hive-metastore-clean-user-merge-partitions",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": BASE_SPARK_JOBS_PATH + "sync_metastore_tables_partitions.py",
            "parameters": [
                DATALAKE_BUCKET,
                LayerEnum.CLEAN.value,
                DAG_NAME,
                "--table-name",
                "170698_user_merge",
            ],
        }
    },
)

propagate_table_metadata_clean_user_merge_task = QuintoAndarDatabricksSubmitRunOperator(
    dag=dag,
    task_id=f"propagate-table-metadata-clean-user-merge",
    json={
        "spark_python_task": {
            "python_file": BASE_SPARK_JOBS_PATH + "propagate_table_metadata.py",
            "parameters": [
                LayerEnum.CLEAN.value,
                MetadataTypeEnum.LINEAGE.value,
                DAG_NAME,
                "170698_user_merge",
            ],
        }
    },
)

update_clean_events_daily_partition_athena_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="update-clean-events-daily-partition-athena",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": UPDATE_ATHENA_TABLE_DAILY_PARTITION_FILE_PATH,
            "parameters": [
                "{{ ds }}",
                ENV,
                DATALAKE_BUCKET,
                ATHENA_QUERY_RESULT_LOCATION,
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
            "python_file": CREATE_CLEAN_STAGING_EVENTS_FILE_PATH,
            "parameters": [
                "{{ ds }}",
                ENV,
                DATALAKE_BUCKET,
                "amplitude",
                "events",
                "--partition_by",
            ]
            + ["id_app", "event_type"]
            + DEFAULT_PARTITION_BY,
        }
    },
)

update_clean_staging_subpartitions_values_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="update-clean-staging-subpartitions-values",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": UPDATE_CLEAN_STAGING_SUBPARTITIONS_VALUES_FILE_PATH,
            "parameters": [
                "{{ ds }}",
                ENV,
                DATALAKE_BUCKET,
                "amplitude",
                "events",
                "--subpartitions",
            ]
            + ["id_app", "event_type"],
        }
    },
)

create_clean_staging_subpartitioned_tables_spark_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="create-clean-staging-subpartitioned-tables-spark",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": CREATE_CLEAN_STAGING_SUBPARTITIONED_TABLES_FILE_PATH,
            "parameters": [
                "{{ ds }}",
                ENV,
                DATALAKE_BUCKET,
                ATHENA_QUERY_RESULT_LOCATION,
                "amplitude",
                "events",
                "--spark",
            ],
        }
    },
)

create_clean_staging_subpartitioned_tables_athena_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="create-clean-staging-subpartitioned-tables-athena",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": CREATE_CLEAN_STAGING_SUBPARTITIONED_TABLES_FILE_PATH,
            "parameters": [
                "{{ ds }}",
                ENV,
                DATALAKE_BUCKET,
                ATHENA_QUERY_RESULT_LOCATION,
                "amplitude",
                "events",
                "--athena",
            ],
        }
    },
)

update_clean_staging_subpartitioned_tables_spark_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="update-clean-staging-subpartitioned-tables-spark",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": UPDATE_CLEAN_STAGING_SUBPARTITIONED_TABLES_FILE_PATH,
            "parameters": [
                "{{ ds }}",
                ENV,
                DATALAKE_BUCKET,
                ATHENA_QUERY_RESULT_LOCATION,
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
            "python_file": BASE_SPARK_JOBS_PATH + "sync_metastore_tables_structure.py",
            "parameters": [
                DATALAKE_BUCKET,
                LayerEnum.CLEAN_STAGING.value,
                DAG_NAME,
                "--all-tables",
            ],
        }
    },
)

sync_metastore_clean_staging_tables_partitions_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="sync-hive-metastore-clean-staging-tables-partitions",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": BASE_SPARK_JOBS_PATH + "sync_metastore_tables_partitions.py",
            "parameters": [
                DATALAKE_BUCKET,
                LayerEnum.CLEAN_STAGING.value,
                DAG_NAME,
                "--all-tables",
            ],
        }
    },
)

propagate_tables_metadata_clean_staging_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="propagate-tables-metadata-clean-staging",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": PROPAGATE_TABLES_METADATA_CLEAN_STAGING_FILE_PATH,
            "parameters": ["{{ ds }}"],
        }
    },
)

update_clean_staging_subpartitioned_tables_athena_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="update-clean-staging-subpartitioned-tables-athena",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": UPDATE_CLEAN_STAGING_SUBPARTITIONED_TABLES_FILE_PATH,
            "parameters": [
                "{{ ds }}",
                ENV,
                DATALAKE_BUCKET,
                ATHENA_QUERY_RESULT_LOCATION,
                "amplitude",
                "--athena",
            ],
        }
    },
)

# load_subpartitioned_event_tables_to_clean_task = QuintoAndarDatabricksSubmitRunOperator(
#     task_id="load-subpartitioned-event-tables-to-clean",
#     dag=dag,
#     json={
#         "spark_python_task": {
#             "python_file": LOAD_SUBPARTITIONED_EVENT_TABLES_TO_CLEAN_FILE_PATH,
#             "parameters": [
#                 "{{ ds }}",
#                 ENV,
#                 DATALAKE_BUCKET,
#                 "amplitude",
#                 "--partition_by",
#             ]
#             + DEFAULT_PARTITION_BY,
#         }
#     },
# )

# sync_metastore_clean_subpartitioned_events_tables_structure_task = QuintoAndarDatabricksSubmitRunOperator(
#     task_id="sync-metastore-clean-subpartitioned-event-tables-structure",
#     dag=dag,
#     json={
#         "spark_python_task": {
#             "python_file": BASE_SPARK_JOBS_PATH + "sync_metastore_tables_structure.py",
#             "parameters": [
#                 DATALAKE_BUCKET,
#                 LayerEnum.CLEAN.value,
#                 DAG_NAME,
#                 "--all-tables",
#             ],
#         }
#     },
# )
#
# sync_metastore_clean_subpartitioned_events_tables_partitions_task = QuintoAndarDatabricksSubmitRunOperator(
#     task_id="sync-hive-metastore-clean-subpartitioned-events-tables-partitions",
#     dag=dag,
#     json={
#         "spark_python_task": {
#             "python_file": BASE_SPARK_JOBS_PATH + "sync_metastore_tables_partitions.py",
#             "parameters": [
#                 DATALAKE_BUCKET,
#                 LayerEnum.CLEAN.value,
#                 DAG_NAME,
#                 "--all-tables",
#             ],
#         }
#     },
# )
#
# propagate_clean_tables_metadata_task = QuintoAndarDatabricksSubmitRunOperator(
#     task_id="propagate-clean-tables-metadata-task",
#     dag=dag,
#     json={
#         "spark_python_task": {
#             "python_file": PROPAGATE_CLEAN_TABLES_METADATA_FILE_PATH,
#             "parameters": ["{{ ds }}"],
#         }
#     },
# )

airflow_helpers.chain(
    create_cluster_task,
    events_to_datalake_raw_task,
    sync_metastore_raw_events_structure_task,
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

airflow_helpers.chain(
    events_to_datalake_raw_task,
    user_merge_raw_to_clean_task,
    sync_metastore_clean_user_merge_structure_task,
    sync_metastore_clean_user_merge_partitions_task,
    propagate_table_metadata_clean_user_merge_task,
    terminate_cluster_task,
)

airflow_helpers.chain(
    events_raw_to_clean_task,
    update_clean_events_daily_partition_athena_task,
    terminate_cluster_task,
)

airflow_helpers.chain(
    events_raw_to_clean_task,
    [create_clean_staging_events_task, update_clean_staging_subpartitions_values_task],
    create_clean_staging_subpartitioned_tables_spark_task,
    [
        create_clean_staging_subpartitioned_tables_athena_task,
        update_clean_staging_subpartitioned_tables_spark_task,
    ],
    terminate_cluster_task,
)

airflow_helpers.chain(
    update_clean_staging_subpartitioned_tables_spark_task,
    sync_metastore_clean_staging_tables_structure_task,
    sync_metastore_clean_staging_tables_partitions_task,
    propagate_tables_metadata_clean_staging_task,
    terminate_cluster_task,
)

airflow_helpers.chain(
    create_clean_staging_subpartitioned_tables_athena_task,
    update_clean_staging_subpartitioned_tables_athena_task,
    terminate_cluster_task,
)

# airflow_helpers.chain(
#     update_clean_staging_subpartitioned_tables_spark_task,
#     load_subpartitioned_event_tables_to_clean_task,
#     sync_metastore_clean_subpartitioned_events_tables_structure_task,
#     sync_metastore_clean_subpartitioned_events_tables_partitions_task,
#     propagate_clean_tables_metadata_task,
#     terminate_cluster_task,
# )


# EC2 temporary dependency
success_logger = QuintoAndarSuccessLoggerOperator(
    dag=dag, bucket="5a-datalake-prod", aws_conn_id="aws_prod_data"
)
terminate_cluster_task >> success_logger
