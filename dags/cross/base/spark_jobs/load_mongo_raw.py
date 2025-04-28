import json
from argparse import ArgumentParser, Namespace
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.clients.db_clients import SparkClient, MongoClient
from bietlejuice.consumers.db_consumers import MongoConsumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.base.spark import SparkDataFrameService

JOB_NAME = "load_mongo_raw"

logger = QuintoAndarLogger(JOB_NAME)


def _load_dataframe_in_datalake(
    df, table_name, is_incremental=False, force_recreate=True, **load_options
):
    """
    Loads the dataframe into the s3 bucket and updates the metastore.
    @param df: DataFrame.
    @param table_name: table name in raw layer.
    @param is_incremental: bool. True indicates that the table will be loaded incrementally.
    By default, this parameter is set to False.
    @param force_recreate: bool. Indicates if it must force table recreation in metastore.
    """
    if not df.rdd.isEmpty():
        logger.info(
            f"m=_load_dataframe_in_datalake, msg=Loading data into s3 bucket..."
        )

        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            partitions=partition_cols if is_incremental else None,
            **load_options,
        )

        spark_metastore_loader.update_metastore(
            df=df,
            database_name=databricks_database_name,
            table_name=table_name,
            format_options=format_options,
            database_location=database_location,
            partitions=partition_cols if is_incremental else [],
            force_recreate=force_recreate,
        )
    else:
        logger.info(
            f"m=_load_dataframe_in_datalake, msg=Dataframe is empty, no data has been loaded to the datalake"
        )


def _extract_table_from_database(
    table_name: str,
    databricks_database_name: str,
    extraction_type: str,
    date_filter_column: str,
    execution_date: str,
    **load_options,
):
    """
    Extracts the data from the table in the Mongo database, considering the
    parameters if it is incremental or full load.
    @param table_name: table name in raw layer.
    @param databricks_database_name: databricks database name used to sink data.
    @param extraction_type: incremental or full.
    @param date_filter_column: column used during incremental loads.
    @param execution_date: airflow execution date.
    """
    logger.info(
        f"m=_extract_table_from_database, msg=Extracting data from Mongo database..."
    )

    if extraction_type == "incremental":
        logger.info(
            f"m=_extract_table_from_database, msg=Performing incremental load..."
        )
        df = mongo_consumer.get_incremental_data_from_table(
            table_name=table_name,
            column_name=date_filter_column,
            execution_date=execution_date,
        )

        df = (
            SparkDataFrameService()
            .input(df)
            .optimize_partition(10000)
            .create_year_month_day_columns_from_date(dt_execution)
            .output()
        )

        _load_dataframe_in_datalake(
            df=df,
            table_name=table_name.lower(),
            is_incremental=True,
            force_recreate=False,
            **load_options,
        )

        spark_metastore_service.create_new_partitions_from_df(
            database_name=databricks_database_name,
            table_name=table_name.lower(),
            df=df,
            partition_cols=partition_cols,
        )
    else:
        logger.info(f"m=_extract_table_from_database, msg=Performing full load...")
        df = mongo_consumer.get_data_from_table(table_name=table_name)

        _load_dataframe_in_datalake(
            df=df, table_name=table_name.lower(), **load_options
        )


def parse_arguments() -> Namespace:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("bucket")
    parser.add_argument("schema")
    parser.add_argument("table_name")
    parser.add_argument("extraction_type")
    parser.add_argument("partition_cols")
    parser.add_argument("date_filter_column")
    parser.add_argument("dbutils_secret_key")
    parser.add_argument("execution_date")
    parser.add_argument(
        "load_options",
        type=str,
        help="S3 load options for spark dataframe, in JSON format",
    )
    parser.add_argument("dbutils_secret_scope")
    parser.add_argument(
        "-tp",
        "--table-privileges",
        type=lambda arg: None if not arg else arg,
        help="json string mapping each principal to a list of permissions for the table",
        required=False,
        default=None,
    )

    return parser.parse_args()


def get_conn_config(dbutils_secret_key: str, dbutils_secret_scope: str) -> dict:
    """Returns the connection configuration from Databricks Secrets."""

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        global dbutils
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(scope=dbutils_secret_scope, key=dbutils_secret_key)

    return json.loads(conn_config_json)


if __name__ == "__main__":
    args = parse_arguments()
    environment = args.env
    datalake_bucket = args.bucket
    schema = args.schema
    table_name = args.table_name
    extraction_type = args.extraction_type
    partition_cols = json.loads(args.partition_cols.replace("'", '"'))
    date_filter_column = args.date_filter_column
    dbutils_secret_key = args.dbutils_secret_key
    dbutils_secret_scope = args.dbutils_secret_scope
    execution_date = args.execution_date
    load_options = json.loads(args.load_options) if args.load_options else {}
    if args.table_privileges is not None:
        table_privileges_dict = json.loads(args.table_privileges)
    else:
        table_privileges_dict = None

    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")

    logger.info(
        f"""
        m=__main__, environment={environment}, dbutils_secret_key={dbutils_secret_key}, datalake_bucket={datalake_bucket},
        schema={schema}, table_name={table_name}, extraction_type={extraction_type},
        date_filter_column={date_filter_column}, partition_cols={partition_cols}, execution_date={execution_date},
        msg=Starting spark job...
        """
    )

    conn_config = get_conn_config(dbutils_secret_key, dbutils_secret_scope)
    spark_client = SparkClient()
    mongo_consumer = MongoConsumer(
        mongo_client=MongoClient(conn_config), spark_client=spark_client
    )

    db_info = DatalakeMetastoreService.get_db_info(environment, schema, datalake_bucket)
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    databricks_database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info(
        f"m=__main__, msg=Creating database in Spark Metastore if not exists..."
    )
    spark_metastore_service.create_database(databricks_database_name)

    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    
    full_raw_table_name = f"{databricks_database_name}.{table_name}"
    if table_privileges_dict is not None:
        table_privileges = TablePrivileges.from_input_dict(
            table_privileges_dict, full_raw_table_name
        )
    else:
        table_privileges = TablePrivileges.from_environment_default(full_raw_table_name)

    _extract_table_from_database(
        table_name=table_name,
        databricks_database_name=databricks_database_name,
        extraction_type=extraction_type,
        date_filter_column=date_filter_column,
        execution_date=execution_date,
        **load_options,
    )
    
    if (
        table_privileges
        and UnityCatalogHelper.is_cluster_unity_catalog_enabled()
    ):
        table_privileges.apply()
