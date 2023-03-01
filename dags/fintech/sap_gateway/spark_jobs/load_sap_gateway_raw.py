import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatabaseEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import PostgresConsumer
from bietlejuice.pipeline import IncrementalTableLoaderPipeline, FullTableLoaderPipeline
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_sap_gateway_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("extraction_type")
    parser.add_argument("execution_date", type=str, help="DAG execution date")
    parser.add_argument("date_filter_column", help="Date filter column", default=None)
    parser.add_argument("build_query", help="Build SQL query", default=None)

    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    extraction_type = args.extraction_type
    execution_date = args.execution_date
    date_filter_column = args.date_filter_column if args.date_filter_column != "None" else None
    build_query = args.build_query if args.build_query != "None" else None
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
        date_filter_column={date_filter_column}, execution_date={execution_date}, msg=Starting Spark job...
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.SAP_GATEWAY
    )

    conn_config = json.loads(conn_config_json)
    spark_client = SparkClient()

    postgres_consumer = PostgresConsumer(conn_config, spark_client)

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
        filter_condition = f"{date_filter_column} BETWEEN DATE('{execution_date}') AND DATE('{execution_date}') + 1 "

        query = f"""
            SELECT
                *,
                CAST(EXTRACT(YEAR FROM DATE({date_filter_column})) AS INT) AS year,
                CAST(EXTRACT(MONTH FROM DATE({date_filter_column})) AS INT) AS month,
                CAST(EXTRACT(DAY FROM DATE({date_filter_column})) AS INT) AS day
            FROM
                "{table_name}"
            WHERE
                {filter_condition}
        """

        if build_query == True:
            query = DAGPackagesPathService.get_query_file_content_in_spark_jobs(
                dag_name=source, layer=LayerEnum.RAW.value, table_name=table_name
            )
            df = postgres_consumer.get_data_from_query(query)
        else:
            df = postgres_consumer.get_incremental_data_by_granularity_from_table(table_name, date_filter_column, execution_date)

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
