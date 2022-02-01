import json
import os
import logging

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.base.athena import TableStorageFormat
from bietlejuice.jobs.composer.base.db import (
    DatabaseEnum,
    DatalakeMetastoreService,
    QUERIES_DATALAKE_PATH,
)
from bietlejuice.jobs.composer.base.pipeline import EnvironmentEnum, LayerEnum
from bietlejuice.jobs.composer.base.spark import (
    BaseSparkContext,
    SparkMetastoreHelper,
    SparkTableStorageFormat,
)
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.dags.base.spark_jobs.sync_metastore_tables_structure import (
    HiveMetastoreSynchronization as HiveMetastoreStructureSynchronization,
)
from bietlejuice.jobs.composer.dags.base.spark_jobs.sync_metastore_tables_partitions import (
    HiveMetastoreSynchronization as HiveMetastorePartitionsSynchronization,
)
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.pipeline.create_external_table_pipeline import (
    CreateExternalTablePipeline,
)
from bietlejuice.jobs.composer.services import ConfigurationService, FileService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService


JOB_NAME = "load_full_quintoandar_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def sync_hive(schema, layer, datalake_bucket, all_tables=True) -> None:
    hm_confs = dbutils.secrets.get(  # noqa: F821
        "quintoandar", DatabaseEnum.HIVE_METASTORE
    )
    hm_confs_json = json.loads(hm_confs)
    _hms_host = hm_confs_json["host"]

    spark_ms = SparkMetastoreHelper(
        datalake_bucket, layer, schema, table_name=None, all_tables=all_tables
    )
    spark_ms.validate_table_arguments()

    tables_metadata = spark_ms.get_all_tables_metadata()
    spark_table_names = list(tables_metadata.keys())

    hms_sync_structure = HiveMetastoreStructureSynchronization(
        _hms_host, layer, spark_ms.spark_database_name, spark_ms.database_location
    )

    # Sync structure
    rdd = BaseSparkContext.sc.parallelize(spark_table_names)
    rdd.foreach(
        lambda _table_name: hms_sync_structure.sync_table(
            tables_metadata.get(_table_name)
        )
    )

    # Sync partitions
    hms_sync_partitions = HiveMetastorePartitionsSynchronization(
        _hms_host, layer, spark_ms.spark_database_name
    )

    rdd.foreach(
        lambda _table_name: hms_sync_partitions.sync_table_partitions(
            tables_metadata.get(_table_name)
        )
    )


environment = EnvironmentEnum.FORNO  # Change to the environment where you will run it.
os.environ["ENVIRONMENT"] = environment  # Necessary to use the ConfigurationService.
layer = LayerEnum.ENRICH.value
schema = "quintoandar"
queries_path = f"{QUERIES_DATALAKE_PATH}{schema}/"

config_service = ConfigurationService(schema)
datalake_bucket = config_service.get_config("datalake_bucket")
athena_query_results_bucket = config_service.get_config("athena_query_results_bucket")

logger.info(
    f"""
m=load_full_quintoandar_into_datalake, environment={environment}, datalake_bucket={datalake_bucket},
, schema={schema}, msg=Starting spark job...
"""
)


# Get tables from sql files
logger.info(f"""msg=Getting tables from schema {schema}...""")
tables = [
    FileService.remove_file_extension(file)
    for file in FileService.list_files(queries_path)
]

# Get standard names for database
db_info = DatalakeMetastoreService.get_db_info(environment, schema, datalake_bucket)
database_name = db_info[f"db_{layer}_databricks"]
format_options = SparkTableStorageFormat.DEFAULT_ENRICH
athena_format_options = TableStorageFormat.get_storage(layer)
database_location = db_info[f"db_{layer}_path"]
athena_database_name = db_info[f"db_{layer}_athena"]

spark_client = SparkClient()
metastore_service = SparkMetastoreService(spark_client)
s3_loader = S3Loader()
spark_metastore_loader = SparkMetastoreLoader(metastore_service)

logger.info("msg=Creating database in Spark Metastore if not exists...")
metastore_service.create_database(database_name)

for table in tables:
    query_path = f"{queries_path}{table}.sql"
    query = FileService.get_query_from_file_name(query_path)
    df = spark_client.get_records(query)

    s3_loader.load_df(
        df=df, s3_path=f"{database_location}{table}", format_options=format_options
    )
    spark_metastore_loader.update_metastore(
        df, database_name, table, format_options, database_location
    )

    # Create external table in Athena

    create_external_table_pipeline = CreateExternalTablePipeline(
        athena_query_result_location=athena_query_results_bucket,
        athena_database_name=athena_database_name,
        table_name=table,
        database_location=database_location,
        format_options=athena_format_options,
        spark_database_name=database_name,
    )
    create_external_table_pipeline.run()

# Sync Hive Metastore
sync_hive(schema, layer, datalake_bucket)

logger.info(f"m={JOB_NAME}, msg=Finished synchronization.")
