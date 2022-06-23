import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import (
    DB_SQL_PATH,
    DatabaseEnum,
    DWMetastoreService,
)
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import (
    SparkClient,
    AthenaClient,
    PostgresClient,
)
from bietlejuice.jobs.composer.consumers.db_consumers import PostgresConsumer
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader
from bietlejuice.jobs.composer.services.file_service import FileService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from pyspark.sql.functions import col


JOB_NAME = "create_datamart_table_in_datalake"

DW_QUERY_TEMPLATE = f"""
DROP TABLE IF EXISTS datamarts.{{table_name}};
CREATE TABLE datamarts.{{table_name}} AS ({{query}});
GRANT ALL ON datamarts.{{table_name}} TO GROUP ETL;
"""

SELECT_FROM_DW = "SELECT * FROM datamarts.{table_name}"


logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

parser = ArgumentParser(description=JOB_NAME)
parser.add_argument("env")
parser.add_argument("dw_bucket")
parser.add_argument("athena_query_results_bucket")
parser.add_argument("dw_schema")
parser.add_argument("schema")
parser.add_argument("table")
parser.add_argument("sql_file")
parser.add_argument("runs_on")

if __name__ == "__main__":
    args = parser.parse_args()
    env = args.env
    dw_bucket = args.dw_bucket
    athena_query_results_bucket = args.athena_query_results_bucket
    dw_schema = args.dw_schema
    schema = args.schema  # TODO this schema is not used
    table = args.table
    sql_file = args.sql_file
    runs_on = args.runs_on

    # check if query_path is diff from built one and raise warning
    query_path = f"{DB_SQL_PATH}/{sql_file}"
    s3_query = FileService.get_query_from_file_name(query_path)

    spark_client = SparkClient()
    # TODO: Needs refactoring. We're using default here because the consumer requests a
    #  database. Please check on DatabricksConsumer.__init__ comments for more
    if runs_on == "athena":
        athena_client = AthenaClient(athena_query_results_bucket)
        query_execution_id = athena_client.run(s3_query, return_query_id=True)
        s3_result_path = f"{athena_client.output_location}/{query_execution_id}.csv"
        csv_options = {
            "header": "true",
            "multiLine": "true",
            "escape": '"',
            "quote": '"',
        }
        dm_table_df = (
            spark_client.conn.read.format("csv")
            .options(**csv_options)
            .load(s3_result_path)
        )
        # Force all the columns to be string to keep datamarts as is.
        dm_table_df = dm_table_df.select(
            [col(c).cast("string") for c in dm_table_df.columns]
        )
    elif runs_on == "redshift":
        base_dbutils = BaseDBUtils()
        if base_dbutils.get_dbutils() is not None:
            dbutils = base_dbutils.get_dbutils()

        conn_config_json = dbutils.secrets.get(scope="quintoandar", key=DatabaseEnum.DW)
        create_query = DW_QUERY_TEMPLATE.format(table_name=table, query=s3_query)
        select_query = SELECT_FROM_DW.format(table_name=table)
        conn_config = json.loads(conn_config_json)
        postgres_client = PostgresClient(
            dbname=conn_config["db"],
            host=conn_config["host"],
            port=conn_config["port"],
            user=conn_config["user"],
            password=conn_config["pwd"],
            keepalives_idle=200,
        )
        postgres_consumer = PostgresConsumer(conn_config, spark_client)
        postgres_client.run(create_query)
        dm_table_df = postgres_consumer.get_data_from_query(select_query)
    else:
        raise Exception(f"datamarts must be defined with a runs_on athena or redshift.")

    dm_table_df = SparkDataFrameService(dm_table_df).optimize_partition(250000).output()

    dw_db_info = DWMetastoreService.get_dw_info(env, dw_schema, dw_bucket)
    metastore_service = SparkMetastoreService(spark_client)
    database_name = dw_db_info["dw_schema_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_DW
    database_location = dw_db_info["dw_schema_path"]
    metastore_service.create_database(database_name)

    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)
    s3_loader.load_full_table(
        df=dm_table_df,
        database_name=database_name,
        table_name=table,
        format_options=format_options,
        database_location=database_location,
    )

    spark_metastore_loader.update_metastore(
        dm_table_df, database_name, table, format_options, database_location
    )
