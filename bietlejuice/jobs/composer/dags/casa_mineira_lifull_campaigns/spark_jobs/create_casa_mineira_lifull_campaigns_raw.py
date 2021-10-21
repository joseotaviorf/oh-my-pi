from argparse import ArgumentParser
from collections import OrderedDict

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

JOB_NAME = "create_casa_mineira_lifull_campaigns_raw"

logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source

    config_service = ConfigurationService(source)
    raw_partition_cols = config_service.get_config("raw_partition_cols")
    table_name = config_service.get_config("raw_table_name")
    table_schema = OrderedDict(config_service.get_config("schema"))

    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, source, datalake_bucket
    )

    database_name = datalake_info["db_raw_databricks"]
    table_path = datalake_info["db_raw_path"]

    spark_metastore_service.create_database(database_name)
    spark_metastore_loader.recreate_table(
        database_name=database_name,
        table_name=table_name,
        new_schema=table_schema,
        s3_path=f'{table_path}{table_name}',
        format_options=SparkTableStorageFormat.DEFAULT_RAW,
        partitions=raw_partition_cols,
    )
