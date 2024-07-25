import json
import logging
from argparse import ArgumentParser, Namespace

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import PostgresConsumer
from bietlejuice.pipeline import IncrementalTableLoaderPipeline, FullTableLoaderPipeline
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_postgres_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def parse_arguments() -> Namespace:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("dbutils_secret_key")
    parser.add_argument("schema")
    parser.add_argument("table_name")
    parser.add_argument("unixtime_measure")
    parser.add_argument("extraction_type")
    parser.add_argument("partition_cols")
    parser.add_argument("date_filter_column")
    parser.add_argument("execution_date")
    parser.add_argument("db_schema")
    parser.add_argument(
        "load_options",
        type=str,
        help="S3 load options for spark dataframe, in JSON format",
    )
    parser.add_argument("read_from_sql")
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")
    parser.add_argument("dbutils_secret_scope")

    return parser.parse_args()


def get_conn_config(dbutils_secret_key: str, dbutils_secret_scope: str) -> dict:
    """Returns the connection configuration from Databricks Secrets."""

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        global dbutils
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(scope=dbutils_secret_scope, key=dbutils_secret_key)

    return json.loads(conn_config_json)


def main():
    args = parse_arguments()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    dbutils_secret_key = args.dbutils_secret_key
    schema = args.schema
    table_name = args.table_name
    unixtime_measure = args.unixtime_measure or None
    extraction_type = args.extraction_type
    is_incremental = extraction_type == "incremental"
    partition_cols = json.loads(args.partition_cols.replace("'", '"'))
    date_filter_column = args.date_filter_column
    execution_date = args.execution_date
    db_schema = args.db_schema
    load_options = json.loads(args.load_options) if args.load_options else {}
    read_from_sql = True if args.read_from_sql.lower() == "true" else False
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date

    logger.info(
        f"""
        m=__main__, environment={environment}, dbutils_secret_key={dbutils_secret_key}, datalake_bucket={datalake_bucket},
        schema={schema}, table_name={table_name}, unixtime_measure={unixtime_measure}, extraction_type={extraction_type},
        date_filter_column={date_filter_column}, partition_cols={partition_cols}, execution_date={execution_date},
        db_schema={db_schema}, load_options={load_options}, load_start_date={load_start_date}, load_end_date={load_end_date}
        msg=Starting spark job...
        """
    )

    conn_config = get_conn_config(dbutils_secret_key, args.dbutils_secret_scope)
    conn_config["schema"] = db_schema
    spark_client = SparkClient()
    postgres_consumer = PostgresConsumer(conn_config, spark_client)

    format_options = SparkTableStorageFormat.DEFAULT_RAW

    db_info = DatalakeMetastoreService.get_db_info(environment, schema, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)

    if read_from_sql:
        query = DAGPackagesPathService.get_query_file_content_in_spark_jobs(
            dag_name=schema, layer=LayerEnum.RAW.value, table_name=table_name
        )

    if is_incremental:
        if read_from_sql:
            df = postgres_consumer.get_data_from_query(
                query.format(execution_date=execution_date)
            )
        else:
            df = postgres_consumer.get_incremental_data_by_processing_window(
                table_name=table_name,
                date_filter_column=date_filter_column,
                load_start_date=load_start_date,
                load_end_date=load_end_date,
                unixtime_measure=unixtime_measure,
            )

        IncrementalTableLoaderPipeline(
            database_name,
            table_name.lower(),
            database_location,
            LayerEnum.RAW,
            None,
            partition_cols,
        ).load_and_register(df, format_options, **load_options)
    else:
        if read_from_sql:
            df = postgres_consumer.get_data_from_query(query)
        else:
            df = postgres_consumer.get_data_from_table(table_name)

        FullTableLoaderPipeline(
            database_name, table_name.lower(), database_location, LayerEnum.RAW, None
        ).load_and_register(df, format_options, **load_options)


if __name__ == "__main__":
    main()
