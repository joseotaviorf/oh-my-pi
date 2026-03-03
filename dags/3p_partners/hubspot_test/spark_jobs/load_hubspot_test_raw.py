import json
import logging
from argparse import ArgumentParser
from datetime import datetime
from enum import Enum

import pyspark.sql.functions as F
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
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.json_service import JsonService
from quintoandar_hubspot_api_client.factories.endpoint_factory import EndpointFactory
from quintoandar_hubspot_api_client.clients.hubspot_client import HubspotClient

JOB_NAME = "load_hubspot_test_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient()


class HubSpotEncoder(json.JSONEncoder):
    def default(self, o):
        if isinstance(o, datetime):
            return o.isoformat()

        return json.JSONEncoder.default(self, o)


class HubSpotSchemaEnum(Enum):
    """Spark schemas for the tables loaded by the HubSpot Consumer."""

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
    environment, datalake_bucket, source, custom_schema, data_interval_start, table = (
        parse_arguments()
    )
    logger.info(
        f"m=main, environment={environment}, datalake_bucket={datalake_bucket}, "
        f"source={source}, custom_schema={custom_schema}, "
        f"data_interval_start={data_interval_start}, table={table}, "
        f"msg=Starting Spark job..."
    )

    config_service = ConfigurationService(source)
    tables = get_tables(config_service, data_interval_start, table)
    transform_tables_into_dataframes(tables)
    load_table_dataframes_into_datalake(
        tables, environment, custom_schema, datalake_bucket, data_interval_start
    )


def parse_arguments():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("custom_schema")
    parser.add_argument("data_interval_start")
    parser.add_argument("table")

    args = parser.parse_args()

    return (
        args.env,
        args.datalake_bucket,
        args.source,
        args.custom_schema,
        args.data_interval_start,
        args.table,
    )


def get_token():
    global dbutils
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    json_credentials = dbutils.secrets.get(scope="quintoandar", key=APIEnum.HUBSPOT)

    return json.loads(json_credentials)["token"]


def get_tables(config_service, execution_date, table):
    """Returns all the tables from the API in the form of a dictionary."""

    hubspot_client = HubspotClient(get_token())
    factory = EndpointFactory(hubspot_client)

    tables = config_service.get_config(table)

    if "params" in tables:
        tables = {table: tables}

    table_results = {}
    for table_name, table_configs in tables.items():
        kwargs = table_configs.get("params", {})
        if "ids_list" in table_configs:
            ids_list_results = factory.build(
                table_configs["ids_list"]["endpoint"], execution_date
            ).sync()
            key = table_configs["ids_list"]["key"]
            kwargs["ids_list"] = [result[key] for result in ids_list_results]

        consumer = factory.build(table_name, execution_date)

        table_results[table_name] = {
            "content": consumer.sync(**kwargs),
            "schema": table_configs.get("schema", None),
            "encode_inner_dictionaries": table_configs.get(
                "encode_inner_dictionaries", False
            ),
        }
        if table_configs.get("bring_archived"):
            table_results[table_name]["archived_content"] = consumer.sync(
                **kwargs, archived=True
            )

    return table_results


def generate_schema(data: dict) -> list:
    """
    Given a raw dictionary containing the result from the consumer, creates a
    schema with only strings except for created_at and updated_at which become timestamps.
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
    """Transforms all tables in the dictionary into dataframes."""

    for table in tables.values():
        if "schema" not in table or table["schema"] is None:
            schema = generate_schema(table["content"])
        else:
            schema = HubSpotSchemaEnum[table["schema"].upper() + "_SCHEMA"].value

        table["dataframe"] = create_dataframe_with_schema(
            table["content"], schema, table["encode_inner_dictionaries"]
        )

        if table["dataframe"] is None:
            continue

        if "archived_content" in table:
            archived_df = create_dataframe_with_schema(
                table["archived_content"], schema, table["encode_inner_dictionaries"]
            )

            if archived_df is not None:
                table["dataframe"] = table["dataframe"].unionAll(
                    archived_df
                ).withColumn(
                    "updated_at",
                    F.greatest(F.col("updated_at"), F.col("archived_at")),
                )


def create_dataframe_with_schema(
    table_content: dict, schema: StructType, encode_inner_dictionaries: bool
):
    """Receives the raw content returned by the consumer, and returns a Spark Dataframe."""

    if not table_content:
        logger.info("No data to convert into dataframe.")
        return None

    if encode_inner_dictionaries:
        table_content = JsonService.transform_json_list_terms(
            table_content, cls=HubSpotEncoder
        )
    return spark_client.create_dataframe(table_content, schema)


def load_table_dataframes_into_datalake(
    tables, environment, custom_schema, datalake_bucket, data_interval_start
):
    """Loads the dataframes into Delta tables using merge/upsert on id + updated_at."""

    db_info = DatalakeMetastoreService.get_db_info(
        environment, custom_schema, datalake_bucket
    )
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]

    ts_load = datetime.strptime(data_interval_start, "%Y-%m-%d")
    loader = DeltaLoader()

    for table_name, table_content in tables.items():
        df = table_content.get("dataframe")

        if df is None or df.rdd.isEmpty():
            logger.info(f"m=__main__, msg={table_name}'s DataFrame is None or empty")
            continue

        df = df.withColumn("ts_load", F.lit(ts_load))

        loader.load_table(
            table_name=f"{database_name}.{table_name}",
            path=f"{database_location}{table_name}",
            source_df=df,
            merge_on=["id", "updated_at"],
        )


if __name__ == "__main__":
    main()
