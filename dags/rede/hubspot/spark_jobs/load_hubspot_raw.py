import json
import logging
from argparse import ArgumentParser
from datetime import datetime
from enum import Enum

from quintoandar_logger import QuintoAndarLogger

from pyspark.sql.types import (
    StructType,
    StructField,
    StringType,
    IntegerType,
    TimestampType,
    BooleanType,
    MapType,
    ArrayType,
)

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.pipeline import IncrementalTableLoaderPipeline, FullTableLoaderPipeline
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.json_service import JsonService
from bietlejuice.services.metastore_services import SparkMetastoreService
from pyspark.sql.functions import greatest, col
from quintoandar_hubspot_api_client.factories.endpoint_factory import EndpointFactory
from quintoandar_hubspot_api_client.clients.hubspot_client import HubspotClient

JOB_NAME = "load_hubspot_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient()

class HubSpotEncoder(json.JSONEncoder):
    def default(self, o):
        if isinstance(o, datetime):
            return o.isoformat()

        return json.JSONEncoder.default(self, o)

class HubSpotSchemaEnum(Enum):
    """This class contains the Spark schemas for the tables loaded by the HubSpot Consumer."""

    PIPELINE_SCHEMA = StructType(
        [
            StructField("label", StringType(), True),
            StructField("display_order", IntegerType(), True),
            StructField("id", StringType(), True),
            StructField(
                "stages",
                ArrayType(
                    StructType(
                        [
                            StructField("label", StringType(), True),
                            StructField("display_order", IntegerType(), True),
                            StructField(
                                "metadata", MapType(StringType(), StringType()), True
                            ),
                            StructField("id", StringType(), True),
                            StructField("created_at", TimestampType(), True),
                            StructField("archived_at", TimestampType(), True),
                            StructField("updated_at", TimestampType(), True),
                            StructField("archived", BooleanType(), True),
                        ]
                    )
                ),
                True,
            ),
            StructField("created_at", TimestampType(), True),
            StructField("archived_at", TimestampType(), True),
            StructField("updated_at", TimestampType(), True),
            StructField("archived", BooleanType(), True),
        ]
    )
    TEAM_SCHEMA = StructType(
        [
            StructField("id", StringType(), True),
            StructField("name", StringType(), True),
            StructField("user_ids", ArrayType(StringType()), True),
            StructField("secondary_user_ids", ArrayType(StringType()), True),
        ]
    )
    OWNER_SCHEMA = StructType(
        [
            StructField("id", StringType(), True),
            StructField("email", StringType(), True),
            StructField("firstName", StringType(), True),
            StructField("lastName", StringType(), True),
            StructField("user_id", IntegerType(), True),
            StructField("created_at", TimestampType(), True),
            StructField("updated_at", TimestampType(), True),
            StructField("archived", BooleanType(), True),
            StructField(
                "teams",
                ArrayType(
                    StructType(
                        [
                            StructField("id", StringType(), True),
                            StructField("name", StringType(), True),
                            StructField("membership", StringType(), True),
                        ]
                    )
                ),
            ),
            StructField("archived_at", TimestampType(), True),
        ]
    )
    OBJECT_SCHEMA = StructType(
        [
            StructField("id", StringType(), True),
            StructField("properties", StringType(), True),
            StructField("properties_with_history", StringType(), True),
            StructField("created_at", TimestampType(), True),
            StructField("updated_at", TimestampType(), True),
            StructField("archived", BooleanType(), True),
            StructField("archived_at", TimestampType(), True),
            StructField("associations", StringType(), True),
        ]
    )



def main():
    environment, datalake_bucket, source, execution_date = parse_arguments()
    logger.info(
        f"""
        m=main, environment={environment}, datalake_bucket={datalake_bucket}, source={source}, execution_date={execution_date}
         msg=Starting Spark job...
        """
    )

    config_service = ConfigurationService(source)
    tables = get_tables(config_service, execution_date)
    transform_tables_into_dataframes(tables)
    load_table_dataframes_into_datalake(
        tables, environment, source, datalake_bucket, execution_date
    )


def parse_arguments():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("execution_date")

    args = parser.parse_args()

    return args.env, args.datalake_bucket, args.source, args.execution_date


def get_token():
    global dbutils
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    json_credentials = dbutils.secrets.get(scope="quintoandar", key=APIEnum.HUBSPOT)

    return json.loads(json_credentials)["token"]


def get_tables(config_service, execution_date):
    """Returns all the tables from the API in the form of a dictionary"""

    hubspot_client = HubspotClient(get_token())
    factory = EndpointFactory(hubspot_client)
    
    tables = config_service.get_config("tables")
    table_results = {}
    for table_name, table_configs in tables.items():
        kwargs = table_configs.get("params", {})
        if "ids_list" in table_configs:
            ids_list_results = factory.build(table_configs["ids_list"]["endpoint"], execution_date).sync()
            key = table_configs["ids_list"]["key"]
            kwargs["ids_list"] = [result[key] for result in ids_list_results]

        consumer = factory.build(table_name, execution_date)

        table_results[table_name] = {
            "content": consumer.sync(**kwargs),
            "is_incremental": table_configs["is_incremental"],
            "schema": table_configs.get("schema", None),
            "encode_inner_dictionaries": table_configs.get("encode_inner_dictionaries", False),
            "date_filter_column": table_configs.get("date_filter_column", None),
        }
        if table_configs.get("bring_archived"):
            table_results[table_name]["archived_content"] = consumer.sync(
                **kwargs, archived=True
            )

    return table_results


def generate_schema(data: dict) -> list:
    """
    Given a raw dictionary containing the result from the consumer, creates a schema with only strings except for created_at and updated_at,
    which become timestamps.
    """
    if len(data):
        columns = data[0].keys()
        type_array = []
        for column_name in columns:
            if column_name in ("created_at", "updated_at"):
                type_array.append(StructField(column_name, TimestampType()))
            else:
                type_array.append(StructField(column_name, StringType()))
        schema = StructType(type_array)
        return schema


def transform_tables_into_dataframes(tables: dict) -> None:
    """Transforms all tables in the dictionary into dataframes, assigning the result to the key 'dataframe'."""

    for table in tables.values():
        if "schema" not in table or table["schema"] is None:
            schema = generate_schema(table["content"])
        else:
            schema = HubSpotSchemaEnum[table["schema"].upper() + "_SCHEMA"].value

        table["dataframe"] = create_dataframe_with_schema(table["content"], schema, table["encode_inner_dictionaries"])
        
        if table["dataframe"] is None:
            continue
        
        if "archived_content" in table:
            archived_df = create_dataframe_with_schema(table["archived_content"], schema, table["encode_inner_dictionaries"])
            
            if archived_df is not None:
                table["dataframe"] = (
                    table["dataframe"]
                    .unionAll(archived_df)
                    .withColumn(
                        "updated_at", greatest(col("updated_at"), col("archived_at"))
                    )
                )


def create_dataframe_with_schema(table_content: dict, schema: StructType, encode_inner_dictionaries: bool):
    """Receives the raw content returned by the consumer, and returns a Spark Dataframe"""
    
    if not table_content:  # Verifies if the data frame is empty
        logger.info("No data to convert into dataframe.")
        return None

    if encode_inner_dictionaries:
        table_content = JsonService.transform_json_list_terms(
          table_content, cls=HubSpotEncoder
        )
    return spark_client.create_dataframe(table_content, schema)


def create_date_partitions(df, date_filter_column):
    """Creates the columns year, month and day using updated_at"""

    return (
        SparkDataFrameService()
        .input(df)
        .create_year_month_day_columns_from_dataframe_column(date_filter_column)
        .output()
    )


def filter_dataframe_by_execution_date(df, execution_date):
    """Filters the rows where in which the day, month and year match the execution date"""

    return df.where(
        f"year = YEAR('{execution_date}') AND month = MONTH('{execution_date}') AND day = DAY('{execution_date}')"
    )


def load_table_dataframes_into_datalake(
    tables, environment, source, datalake_bucket, execution_date
):
    """Loads the dataframes into S3, either incrementally or fully, depending on the config."""

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)

    partition_cols = ["year", "month", "day"]

    for table_name, table_content in tables.items():
        df = table_content.get("dataframe")

        if df is None or df.rdd.isEmpty():
            logger.info(f"m=__main__, msg={table_name}'s DataFrame is None or empty")
            continue

        if table_content["is_incremental"]:
            df = create_date_partitions(df, table_content["date_filter_column"])
            df = filter_dataframe_by_execution_date(df, execution_date)
            IncrementalTableLoaderPipeline(
                database_name,
                table_name,
                database_location,
                LayerEnum.RAW,
                None,
                partition_cols,
            ).load_and_register(df, format_options)
        else:
            FullTableLoaderPipeline(
                database_name, table_name, database_location, LayerEnum.RAW, None
            ).load_and_register(df, format_options)


if __name__ == "__main__":
    main()