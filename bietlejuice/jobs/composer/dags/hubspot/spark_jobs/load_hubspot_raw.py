import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from hubspot import HubSpot

from bietlejuice.jobs.composer.base.api.api_enum import APIEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.dags.hubspot.spark_jobs.hubspot_encoder import (
    HubSpotEncoder,
)
from bietlejuice.jobs.composer.dags.hubspot.spark_jobs.schemas import HubSpotSchemaEnum
from bietlejuice.jobs.composer.pipeline import (
    IncrementalTableLoaderPipeline,
    FullTableLoaderPipeline,
)
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)
from bietlejuice.jobs.composer.services.json_service import JsonService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from pyspark.sql.functions import greatest, col

JOB_NAME = "load_hubspot_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient()


def main():
    environment, datalake_bucket, source, execution_date = parse_arguments()
    logger.info(
        f"""
        m=main, environment={environment}, datalake_bucket={datalake_bucket}, source={source}, execution_date={execution_date}
         msg=Starting Spark job...
        """
    )

    config_service = ConfigurationService(source)
    tables = get_tables(config_service)
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


def get_integration_method(table_name, hubspot_client):
    """Returns the method used to call the api given the table name and hubspot client"""

    methods = {
        "contact": lambda **kwargs: fetch_all(
            hubspot_client.crm.contacts.basic_api, **kwargs
        ),
        "company": lambda **kwargs: fetch_all(
            hubspot_client.crm.companies.basic_api, **kwargs
        ),
        "deal": lambda **kwargs: fetch_all(
            hubspot_client.crm.deals.basic_api, **kwargs
        ),
        "ticket": lambda **kwargs: fetch_all(
            hubspot_client.crm.tickets.basic_api, **kwargs
        ),
        "deal_pipeline": hubspot_client.crm.pipelines.pipelines_api.get_all,
        "ticket_pipeline": hubspot_client.crm.pipelines.pipelines_api.get_all,
        "owner": hubspot_client.crm.owners.get_all,
        "team": hubspot_client.settings.users.teams_api.get_all,
    }

    if table_name not in methods:
        raise KeyError(f"The table {table_name} is not valid")

    return methods[table_name]


def get_tables(config_service):
    """Returns all the tables from the API in the form of a dictionary"""

    hubspot_client = HubSpot()
    hubspot_client.access_token = get_token()

    tables = config_service.get_config("tables")

    table_results = {}
    for table_name, table_configs in tables.items():
        kwargs = {
            arg_name: arg_val
            for arg_name, arg_val in table_configs.items()
            if arg_name not in ("is_incremental", "bring_archived")
        }
        get_table_function = get_integration_method(table_name, hubspot_client)
        table_results[table_name] = {
            "content": get_table_function(**kwargs),
            "is_incremental": table_configs["is_incremental"],
        }
        if table_configs.get("bring_archived"):
            table_results[table_name]["archived_content"] = get_table_function(
                **kwargs, archived=True
            )

    return table_results


def fetch_all(base_api_client, **kwargs):
    """
    Given a base api client, returns the table contents.
    This function already exists in HubSpot client, but the paging is fixed as 100, which is above
    the limit to get the history.
    """

    results = []
    after = None

    while True:
        page = base_api_client.get_page(after=after, limit=50, **kwargs)
        results.extend(page.results)
        if page.paging is None:
            break
        after = page.paging.next.after

    return results


def transform_tables_into_dataframes(tables):
    """Transforms all tables in the dictionary into dataframes, assigning the result to the key "dataframe"."""

    transformation_methods = {
        "deal_pipeline": transform_pipeline_table_into_dataframe,
        "ticket_pipeline": transform_pipeline_table_into_dataframe,
        "team": transform_team_table_into_dataframe,
        "owner": transform_owner_table_into_dataframe,
    }

    for table_name, table in tables.items():
        transform_table_into_dataframe = transformation_methods.get(
            table_name, transform_object_table_into_dataframe
        )
        table["dataframe"] = transform_table_into_dataframe(table["content"])
        if "archived_content" in table:
            table["dataframe"] = (
                table["dataframe"]
                .unionAll(transform_table_into_dataframe(table["archived_content"]))
                .withColumn(
                    "updated_at", greatest(col("updated_at"), col("archived_at"))
                )  # HubSpot doesn't change updated_at when it archives an object
            )


def transform_pipeline_table_into_dataframe(table_content):
    """Receives the raw content of a pipeline table returned by the api consumer, and returns a Spark dataframe"""

    schema = HubSpotSchemaEnum.PIPELINE_SCHEMA
    table_dict = table_content.to_dict()["results"]
    return spark_client.create_dataframe(table_dict, schema)


def transform_team_table_into_dataframe(table_content):
    """Receives the raw content of a team table returned by the api consumer, and returns a Spark dataframe"""

    schema = HubSpotSchemaEnum.TEAM_SCHEMA
    table_dict = table_content.to_dict()["results"]
    return spark_client.create_dataframe(table_dict, schema)


def transform_owner_table_into_dataframe(table_content):
    """Receives the raw content of an owner table returned by the api consumer, and returns a Spark dataframe"""

    schema = HubSpotSchemaEnum.OWNER_SCHEMA
    table_dict = list(map(lambda x: x.to_dict(), table_content))
    return spark_client.create_dataframe(table_dict, schema)


def transform_object_table_into_dataframe(table_content):
    """Receives the raw content of a CRM object returned by the api consumer, and returns a Spark dataframe"""

    schema = HubSpotSchemaEnum.OBJECT_SCHEMA
    table_dict = list(map(lambda x: x.to_dict(), table_content))
    unnested_table_dict = JsonService.transform_json_list_terms(
        table_dict, cls=HubSpotEncoder
    )
    return spark_client.create_dataframe(unnested_table_dict, schema)


def create_date_partitions(df):
    """Creates the columns year, month and day using updated_at"""

    return (
        SparkDataFrameService()
        .input(df)
        .create_year_month_day_columns_from_dataframe_column("updated_at")
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
        df = table_content["dataframe"]

        if df.rdd.isEmpty():
            logger.info(f"m=__main__, msg={table_name}'s RDD is empty")
            continue

        if table_content["is_incremental"]:
            df = create_date_partitions(df)
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
