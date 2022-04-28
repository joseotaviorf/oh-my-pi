import json
import logging
from argparse import ArgumentParser
from datetime import datetime, timedelta

from quintoandar_airtable_api_client.clients import AirtableClient
from quintoandar_airtable_api_client.consumers import AirtableConsumer
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.api.api_enum import APIEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import (
    BaseDBUtils,
    BaseSparkContext,
    SparkDataFrameService,
    SparkTableStorageFormat,
)
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.formatters import StringFormatter
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_incremental_airtable_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def extend_incremental_params(params: dict, execution_date: str) -> dict:
    """Function to parse and add incremental param in the current params.

    :param params: Dict with request params
    :type params: dict
    :param execution_date: Execution_date as string
    :type execution_date: str
    :return: Dict of extended params
    :rtype: dict
    """

    dt_started = datetime.strptime(execution_date, "%Y-%m-%d")
    dt_ended = (dt_started + timedelta(days=1)).strftime("%Y-%m-%d")
    filter_by_formula = f"AND( LAST_MODIFIED_TIME() >= '{dt_started}', LAST_MODIFIED_TIME() < '{dt_ended}')"
    params["filterByFormula"] = filter_by_formula

    return params


def parse_records(records: list):
    """Function to parse and convert response records into a dataframe

    :param records: Raw records from consumer/API reponse
    :type records: list[dict]
    :return: Dataframe with formatted columns
    :rtype: Spark Dataframe
    """

    records = [rec["fields"] for rec in records]
    df = BaseSparkContext.sc.parallelize(records).toDF()
    formatted_columns = list(
        map(StringFormatter.set_alphanumeric_snake_case, df.columns)
    )
    df = df.toDF(*formatted_columns)

    return df


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("execution_date")

    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    execution_date = args.execution_date

    config_service = ConfigurationService(source)
    tables = config_service.get_config("tables")
    partitions_cols = config_service.get_config("partition_cols")

    logger.info(
        f"""
                m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
                execution_date={execution_date} msg=Starting spark job...
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    # Initializing clients
    spark_client = SparkClient()
    secrets = dbutils.secrets.get(scope="quintoandar", key=APIEnum.AIRTABLE)
    api_token = json.loads(secrets)["auth_token"]

    airtable_client = AirtableClient(api_token=api_token)
    airtable_consumer = AirtableConsumer(client=airtable_client, path="")

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)

    s3_loader = S3Loader()
    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")

    for table_name in tables:
        table_config = tables[table_name]
        base_id = table_config["base_id"]
        table_id = table_config["table_id"]
        params = table_config.get("params", {})

        extended_params = extend_incremental_params(params, execution_date)

        path = f"{base_id}/{table_id}"
        airtable_consumer.path = path

        records = airtable_consumer.sync(params=extended_params)

        if records:
            df = parse_records(records)
            df = (
                SparkDataFrameService()
                .input(df)
                .create_year_month_day_columns_from_date(dt_execution)
                .output()
            )
            s3_loader.load_df(
                df=df,
                s3_path=f"{database_location}{table_name}",
                format_options=format_options,
                partitions=partitions_cols,
            )

            spark_metastore_loader.update_metastore(
                df,
                database_name,
                table_name,
                format_options,
                database_location,
                partitions_cols,
                force_recreate=False,
            )

            spark_metastore_service.create_new_partitions_from_df(
                database_name=database_name,
                table_name=table_name,
                df=df,
                partition_cols=partitions_cols,
            )
