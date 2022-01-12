import json
import os
import logging

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.base.db import (
    DatabaseEnum,
    DWMetastoreService,
    DW_QUERY_PATH,
)

from bietlejuice.jobs.composer.base.pipeline import EnvironmentEnum, LayerEnum
from bietlejuice.jobs.composer.base.spark import (
    BaseSparkContext,
    SparkMetastoreHelper,
    SparkTableStorageFormat,
)
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.dags.base.spark_jobs.sync_metastore_tables import (
    HiveMetastoreSynchronization,
)
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services import ConfigurationService, FileService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService


JOB_NAME = "load_tables_public_into_dw"

environment = EnvironmentEnum.FORNO  # Change to the environment where you will run it.
os.environ["ENVIRONMENT"] = environment  # Necessary to use the ConfigurationService.
layer = LayerEnum.DW.value
schema = "public"
queries_path = f"{DW_QUERY_PATH}{schema}/"

config_service = ConfigurationService(schema)
dw_bucket = config_service.get_config("dw_bucket")

# List of tables that were created and is going to be sync with Hive  - Insert here all tables that has to be created and sync
tables = ["dim_date"]

# Get standard names for database
db_info = DWMetastoreService.get_dw_info(environment, schema, dw_bucket)
database_name = db_info[f"dw_schema_databricks"]
format_options = SparkTableStorageFormat.DEFAULT_DW
database_location = db_info[f"dw_schema_path"]

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def sync_hive(schema, layer, datalake_bucket, tables, all_tables=True) -> None:
    hm_confs = dbutils.secrets.get("quintoandar", DatabaseEnum.HIVE_METASTORE)
    hm_confs_json = json.loads(hm_confs)
    _hms_host = hm_confs_json["host"]

    spark_ms = SparkMetastoreHelper(
        datalake_bucket, layer, schema, table_name=None, all_tables=all_tables
    )
    spark_ms.validate_table_arguments()

    tables_metadata = spark_ms.get_all_tables_metadata()

    hms_sync = HiveMetastoreSynchronization(
        _hms_host, layer, spark_ms.spark_database_name, spark_ms.database_location
    )

    rdd = BaseSparkContext.sc.parallelize(tables)
    rdd.foreach(
        lambda _table_name: hms_sync.sync_table(tables_metadata.get(_table_name))
    )


logger.info(
    f"""
    m=load_tables_public_into_dw, environment={environment}, dw_bucket={dw_bucket},
    , schema={schema}, msg=Starting spark job...
    """
)

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

logger.info(f"m={JOB_NAME}, msg=Starting tables synchronization...")

sync_hive(schema, layer, dw_bucket, tables)

logger.info(f"m={JOB_NAME}, msg=Finished synchronization.")
