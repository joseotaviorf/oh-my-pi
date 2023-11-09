import json
import logging
from argparse import ArgumentParser
from datetime import datetime, timedelta

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatabaseEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import PostgresConsumer
from bietlejuice.pipeline import IncrementalTableLoaderPipeline, FullTableLoaderPipeline
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_retsuko_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


class PostgesConsumerTwoDaysIncremental(PostgresConsumer):
    @logger
    def get_incremental_data_from_table(
        self, table_name, date_filter_column, date_filter_value, unixtime_measure=None
    ):

        schema = self.conn_config["schema"]

        dt_filter_value = datetime.strptime(date_filter_value, "%Y-%m-%d")
        dt_filter_value_day_after = dt_filter_value + timedelta(days=1)
        dt_filter_value = dt_filter_value - timedelta(days=1)

        if unixtime_measure == "milliseconds":
            filter_value = 1000 * int(dt_filter_value.timestamp())
            filter_value_day_after = 1000 * int(dt_filter_value_day_after.timestamp())
        elif unixtime_measure == "seconds":
            filter_value = int(dt_filter_value.timestamp())
            filter_value_day_after = int(dt_filter_value_day_after.timestamp())
        else:
            filter_value = dt_filter_value
            filter_value_day_after = dt_filter_value_day_after

        filter_enclosement = (
            "{filter}" if unixtime_measure is not None else "'{filter}'"
        )
        query_filter_value = filter_enclosement.format(filter=filter_value)
        query_filter_value_day_after = filter_enclosement.format(
            filter=filter_value_day_after
        )

        query = f"""
            SELECT
                *,
                EXTRACT(YEAR FROM {date_filter_column}) AS year,
                EXTRACT(MONTH FROM {date_filter_column}) AS month,
                EXTRACT(DAY FROM {date_filter_column}) AS day
            FROM
                "{schema}"."{table_name}"
            WHERE
                {date_filter_column} >= {query_filter_value}
                AND {date_filter_column} < {query_filter_value_day_after}
        """

        return self.get_data_from_query(query)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("extraction_type")
    parser.add_argument("execution_date", type=str, help="DAG execution date")
    parser.add_argument("date_filter_column", help="Date filter column", default="None")

    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    extraction_type = args.extraction_type
    execution_date = args.execution_date
    date_filter_column = (
        args.date_filter_column if args.date_filter_column != "None" else None
    )

    config_service = ConfigurationService(source)
    partition_cols = (
        None
        if extraction_type == "full"
        else config_service.get_config("partition_columns")
    )

    logger.info(
        f"""
        m=__main__, environment={environment}, datalake_bucket={datalake_bucket},
        source={source}, table_name={table_name}, raw_partition_cols={partition_cols},
        date_filter_column={date_filter_column}, execution_date={execution_date},
        extraction_type={extraction_type}, msg=Starting Spark job...
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.RETSUKO
    )

    conn_config = json.loads(conn_config_json)
    spark_client = SparkClient()

    postgres_consumer = PostgesConsumerTwoDaysIncremental(conn_config, spark_client)

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    s3_loader = S3Loader()
    table_name = table_name.lower()

    if extraction_type == "incremental":
        df = postgres_consumer.get_incremental_data_from_table(
            table_name, date_filter_column, execution_date
        )
        if not df.rdd.isEmpty():
            logger.info("m=__main__, msg=RDD is not empty. Loading into S3.")
            IncrementalTableLoaderPipeline(
                database_name,
                table_name,
                database_location,
                LayerEnum.RAW,
                None,
                partition_cols,
            ).load_and_register(df, format_options)
        else:
            logger.info("m=__main__, msg=RDD is empty")
    else:
        df = postgres_consumer.get_data_from_table(table_name)
        if not df.rdd.isEmpty():
            logger.info("m=__main__, msg=RDD is not empty. Loading into S3.")
            FullTableLoaderPipeline(
                database_name, table_name, database_location, LayerEnum.RAW, None
            ).load_and_register(df, format_options)
        else:
            logger.info("m=__main__, msg=RDD is empty")
