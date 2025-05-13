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


class NoDataFoundException(Exception):
    """
    No Data Found Exception
    """
    def __init__(self):
        self.message = "No Data Found. Verify if this is a table in use or if is not a unused old column"
        super().__init__(self.message)


def create_table_schema() -> StructType:
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
        ]
    )
    return df_schema


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


def create_query_to_sample_data(column: Row, load_start_date: str) -> str:
    dict_column = column.asDict()

    layer = dict_column["layer"]
    database_name = dict_column["database_name"]
    table_name = dict_column["table_name"]
    column = dict_column["column_name"]

    return f"""
        WITH sample AS (
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
        LIMIT
            10
        )
        SELECT
            CONCAT(database_name, ".", table_name, ".", column_name) AS id_entity,
            layer,
            database_name,
            table_name,
            column_name,
            array_agg(column_value) AS sample,
            'SUCCESS' as status,
            null as error_class,
            null as error_message,
            to_timestamp("{load_start_date}") as ts_ingested
        FROM
        sample
        GROUP BY
        layer,
        database_name,
        table_name,
        column_name
    """


def get_columns_to_sample(spark_client: SparkClient, load_start_date: str, load_end_date: str) -> DataFrame:
    sql = f"""
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
                AND layer in ('enrich')
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
            column_name
        FROM
            columns_datalake AS cd
                LEFT JOIN columns_to_sample AS cts
                    ON cd.id_entity = cts.id_entity
        WHERE
            cts.id_entity IS NULL
    """
    return spark_client.get_records(sql)


def get_sample_data(spark_client: SparkClient, table: Row, execution_date: datetime, partition_cols: list):
    sql = create_query_to_sample_data(table, execution_date.strftime("%Y-%m-%d"))
    df_sample = spark_client.get_records(sql)

    if df_sample.isEmpty():
        raise NoDataFoundException()

    return df_sample


def create_sample_error_register(column: Row, error: Exception, load_start_date: str) -> list:
    dict_column = column.asDict()

    layer = dict_column["layer"]
    database_name = dict_column["database_name"]
    table_name = dict_column["table_name"]
    column = dict_column["column_name"]

    return {
        "id_entity": f"{database_name}.{table_name}.{column}",
        "layer": layer,
        "database_name": database_name,
        "table_name": table_name,
        "column_name": column,
        "status": "FAIL",
        "error_class": f"{error.__class__.__module__}.{error.__class__.__name__}",
        "error_message": str(error)[:300],  # get the first 300 caracter from the error.
        "ts_ingested": datetime.strptime(load_start_date, "%Y-%m-%d")
    }


def get_df_error(spark_client: SparkClient, sample_error: list, schema: StructType):
    return spark_client.create_dataframe(sample_error, schema=schema)


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
df_lake_sample = spark_client.create_dataframe([], create_table_schema())

df_tables_to_sample = get_columns_to_sample(spark_client, load_start_date, load_end_date)
list_tables_to_sample = df_tables_to_sample.collect()

index = 0
size = len(list_tables_to_sample)
for column in list_tables_to_sample:

    table_id = f"{column.database_name}.{column.table_name}"
    entity_id = f"{table_id}.{column.column_name}"

    if table_id not in skip_list:

        try:
            df_sample = get_sample_data(spark_client, column, execution_date, partition_cols)
            df_lake_sample = df_lake_sample.union(df_sample)

        except AnalysisException as exc:
            error_class = exc.getErrorClass()
            if error_class in [DELTA_TABLE_NOT_FOUND, TABLE_OR_VIEW_NOT_FOUND]:
                logging.warning(f"Table {entity_id} not found.")
            elif error_class in [INSUFFICIENT_PERMISSIONS]:
                logging.warning(f"Insufficient permission to read table {entity_id}.")
            else:
                logging.warning(f"Not handled error. Table: {entity_id}. Error: {error_class}")
            sample_error.append(create_sample_error_register(column, exc, load_start_date))

        except Exception as exc:
            logging.warning(f"Exception. Table: {entity_id}. Error: {type(exc)}")
            sample_error.append(create_sample_error_register(column, exc, load_start_date))

df_errors = get_df_error(spark_client, sample_error, create_table_schema())
df_load_sample = df_lake_sample.union(df_errors)
df_load_sample = (
    SparkDataFrameService()
    .input(df_load_sample)
    .create_year_month_day_columns_from_date(execution_date)
    .optimize_partitions_by_partition_columns(partition_cols)
    .output()
)
load_table(df_load_sample, env, datalake_bucket, schema, table_name, merge_on)
