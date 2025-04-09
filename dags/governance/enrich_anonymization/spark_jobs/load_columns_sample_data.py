import ast
import logging
from datetime import datetime
from argparse import ArgumentParser

from pyspark.sql import DataFrame, Row
from pyspark.sql.types import StructType, StructField, StringType, ArrayType, TimestampType, IntegerType
from pyspark.errors import AnalysisException

from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.services import ConfigurationService
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkDataFrameService
from bietlejuice.loaders.delta_loader import DeltaLoader


DELTA_TABLE_NOT_FOUND = "DELTA_TABLE_NOT_FOUND"
TABLE_OR_VIEW_NOT_FOUND = "TABLE_OR_VIEW_NOT_FOUND"
INSUFFICIENT_PERMISSIONS = "INSUFFICIENT_PERMISSIONS"
JOB_NAME = "load_columns_sample_data"

logging.getLogger("py4j").setLevel(logging.ERROR)


def load_table(
    dataframe: DataFrame,
    environment: str,
    datalake_bucket: str,
    schema: str,
    table_name: str,
    merge_on: list = []
) -> None:
    print("m=load_table,msg='loading table'")

    db_info = DatalakeMetastoreService.get_db_info(environment, schema, datalake_bucket)
    database_name = db_info["db_enrich_databricks"]
    database_location = db_info["db_enrich_path"]

    loader = DeltaLoader()
    loader.load_table(
        table_name=f"{database_name}.{table_name}",
        path=f"{database_location}/{table_name}",
        source_df=dataframe,
        merge_on=merge_on,
    )


def create_query_to_sample_data(table: Row, load_start_date: str):
    union_query_sample = ""

    dict_table = table.asDict()

    layer = dict_table["layer"]
    database_name = dict_table["database_name"]
    table_name = dict_table["table_name"]
    columns = dict_table["table_columns"]

    for column in columns:
        column_sample = f"""
            (
            SELECT
                '{layer}' AS layer,
                '{database_name}' AS database_name,
                '{table_name}' AS table_name,
                '{column}' AS column_name,
                CAST({column} AS STRING) AS column_value
            FROM
                {database_name}.{table_name}
            WHERE
                {column} IS NOT NULL
                OR CAST({column} AS STRING) != ''
            LIMIT 10
            )
        """

    if not union_query_sample:
        union_query_sample = column_sample
    else:
        union_query_sample += f" UNION ALL {column_sample}"

    return f"""
        WITH sample AS ({union_query_sample})
        SELECT
            CONCAT(database_name, ".", table_name, ".", column_name) AS id_entity,
            layer,
            database_name,
            table_name,
            column_name,
            array_agg(column_value) AS sample,
            'SUCCESS' as status,
            to_timestamp("{load_start_date}") as ts_ingested
        FROM
            sample
        GROUP BY
            layer,
            database_name,
            table_name,
            column_name
        """


def get_columns_to_sample(spark_client: SparkClient, load_start_date: str, load_end_date: str):
    sql = """
        WITH columns_datalake AS (
        SELECT
            CONCAT(database_name, ".", table_name, ".", column_name) AS id_entity,
            layer,
            database_name,
            table_name,
            column_name
        FROM
            datalake_documentation_metrics_clean.columns_metastore
        WHERE
            MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
            AND layer in ('dw', 'enrich', 'clean')
        ),
        columns_to_sample AS (
        SELECT
            id_entity
        FROM
            datalake_anonymization.columns_sample_data
        )
        SELECT
            layer,
            database_name,
            table_name,
            ARRAY_AGG(column_name) AS table_columns
        FROM
            columns_datalake AS cd
                LEFT JOIN columns_to_sample AS cts
                    ON cd.id_entity = cts.id_entity
        WHERE
            cts.id_entity IS NULL
        GROUP BY
            layer,
            database_name,
            table_name
    """.format(load_start_date=load_start_date, load_end_date=load_end_date)
    return spark_client.get_records(sql)


def get_sample_data(spark_client: SparkClient, table: Row, execution_date: datetime, partition_cols: list):
    sql = create_query_to_sample_data(table, execution_date.strftime("%Y-%m-%d"))
    sample_df = spark_client.get_records(sql)
    return (
        SparkDataFrameService()
        .input(sample_df)
        .create_year_month_day_columns_from_date(execution_date)
        .optimize_partitions_by_partition_columns(partition_cols)
        .output()
    )


def create_table_schema():
    df_schema = StructType(
        [
            StructField("id_entity", StringType(), nullable=True),
            StructField("layer", StringType(), nullable=True),
            StructField("database_name", StringType(), nullable=True),
            StructField("table_name", StringType(), nullable=True),
            StructField("column_name", StringType(), nullable=True),
            StructField("sample", ArrayType(StringType(), containsNull=False), nullable=True),
            StructField("status", StringType(), nullable=True),
            StructField("error_class", StringType(), nullable=True),
            StructField("error_message", StringType(), nullable=True),
            StructField("ts_ingested", TimestampType(), nullable=True),
            StructField("year", IntegerType(), nullable=True),
            StructField("month", IntegerType(), nullable=True),
            StructField("day", IntegerType(), nullable=True),
        ]
    )
    return df_schema


def create_sample_error_register(table: Row, error: Exception, load_start_date: str) -> list:
    dict_table = table.asDict()

    layer = dict_table["layer"]
    database_name = dict_table["database_name"]
    table_name = dict_table["table_name"]
    columns = dict_table["table_columns"]

    sample_error = []
    for column in columns:
        sample_error.append(
            {
                "id_entity": f"{database_name}.{table_name}.{column}",
                "layer": layer,
                "database_name": database_name,
                "table_name": table_name,
                "column_name": column,
                "sample": [""],
                "status": "FAIL",
                "error_class": f"{error.__class__.__module__}.{error.__class__.__name__}",
                "error_message": str(error)[:300], # get the first 300 caracter from the error.
                "ts_ingested": datetime.strptime(load_start_date, "%Y-%m-%d")
            }
        )

    return sample_error


def get_df_error(spark_client: SparkClient, sample_error: list, execution_date: datetime, partition_cols: list):
    schema = create_table_schema()
    df_error = spark_client.create_dataframe(sample_error ,schema=schema)
    return (
        SparkDataFrameService()
        .input(df_error)
        .create_year_month_day_columns_from_date(execution_date)
        .optimize_partitions_by_partition_columns(partition_cols)
        .output()
    )


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str)
    parser.add_argument("datalake_bucket", type=str)
    parser.add_argument("schema", type=str)
    parser.add_argument("table_name", type=str)
    parser.add_argument("load_start_date", type=str)
    parser.add_argument("load_end_date", type=str)
    parser.add_argument("partitions", type=str)
    parser.add_argument("source", type=str)
    parser.add_argument("merge_on", type=str)

    args = parser.parse_args()
    env = args.env
    datalake_bucket = args.datalake_bucket
    schema = args.schema
    table_name = args.table_name
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date
    execution_date = datetime.strptime(load_start_date, "%Y-%m-%d")
    partition_cols = ast.literal_eval(args.partitions)
    source = args.source
    merge_on = ast.literal_eval(args.merge_on)

    config_service = ConfigurationService(source)
    skip_list = config_service.get_config("skip_list")

    spark_client = SparkClient()

    df_tables_to_sample = get_columns_to_sample(spark_client, load_start_date, load_end_date)

    sample_error = []
    list_tables_to_sample = df_tables_to_sample.collect()
    for table in list_tables_to_sample:

        entity_id = f"{table.database_name}.{table.table_name}"
        logging.info(f"Sampling data from table {entity_id}")

        if entity_id not in skip_list:
            try:
                df_sample = get_sample_data(spark_client, table, execution_date, partition_cols)
                load_table(df_sample, env, datalake_bucket, schema, table_name, merge_on)
                logging.info(f"Table {entity_id} sample saved.")
            except AnalysisException as exc:
                error_class = exc.getErrorClass()
                if error_class in [DELTA_TABLE_NOT_FOUND, TABLE_OR_VIEW_NOT_FOUND]:
                    logging.warning(f"Table {entity_id} not found.")
                elif error_class in [INSUFFICIENT_PERMISSIONS]:
                    logging.warning(f"Insufficient permission to read table {entity_id}.")
                else:
                    logging.warning(f"Not handled error. Table: {entity_id}. Error: {error_class}")
                sample_error += create_sample_error_register(table, exc, load_start_date)
            except Exception as exc:
                logging.warning(f"Exception. Table: {entity_id}. Error: {type(exc)}")
                sample_error += create_sample_error_register(table, exc, load_start_date)

    logging.info("Loding tables with error to sample")
    df_errors = get_df_error(spark_client, sample_error, execution_date, partition_cols)
    load_table(df_errors, env, datalake_bucket, schema, table_name, merge_on)
    logging.info("Loaded Errors")
