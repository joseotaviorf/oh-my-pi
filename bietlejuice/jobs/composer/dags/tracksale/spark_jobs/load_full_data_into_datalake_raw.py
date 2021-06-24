import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from quintoandar_tracksale_api_client.clients import TracksaleClient
from quintoandar_tracksale_api_client.consumers import CONSUMERS

from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.api.api_enum import APIEnum
from bietlejuice.jobs.composer.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_full_data_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_api_response(token, endpoint_name):

    tracksale_client = TracksaleClient(api_token=token)
    consumer_instance = CONSUMERS[endpoint_name](tracksale_client)
    api_response = consumer_instance.sync()

    return api_response


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the API")
    parser.add_argument("endpoint_name", help="endpoint to call the API")
    parser.add_argument("campaign_column", help="campaign ID column name")
    parser.add_argument("campaigns_to_block", help="campaigns to be blocked")

    args = parser.parse_args()

    environment = args.environment
    source = args.source
    datalake_bucket = args.datalake_bucket
    endpoint_name = args.endpoint_name
    campaign_column = args.campaign_column
    campaign_column = campaign_column.split(".")
    campaigns_to_block = args.campaigns_to_block
    campaigns_to_block = list(map(int, campaigns_to_block.split(",")))

    logger.info(
        f"m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket}, "
        f"endpoint_name={endpoint_name}, msg=Starting spark job..."
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    json_credentials = dbutils.secrets.get(
        scope=DATABRICKS_SCOPE, key=APIEnum.TRACKSALE
    )
    credentials = json.loads(json_credentials)
    api_response = get_api_response(credentials["token"], endpoint_name)

    if api_response:

        # Currently, dispatch_limits field has all its values as None, so df can't infer the data type
        for resp in api_response:
            if "dispatch_limits" in api_response:
                resp["dispatch_limits"] = json.dumps(resp.get("dispatch_limits"))

        spark_client = SparkClient()
        df = spark_client.create_dataframe(api_response)

        if len(campaign_column) > 1:
            df = df[
                ~df[campaign_column[0]]
                .getItem(campaign_column[1])
                .isin(campaigns_to_block)
            ]
        else:
            df = df[~df[campaign_column[0]].isin(campaigns_to_block)]

        df = SparkDataFrameService().input(df).convert_array_type_to_json().output()

        db_info = DatalakeMetastoreService.get_db_info(
            environment, source, datalake_bucket
        )
        metastore_service = SparkMetastoreService(spark_client)
        spark_metastore_loader = SparkMetastoreLoader(metastore_service)
        s3_loader = S3Loader()

        database_name = db_info["db_raw_databricks"]
        format_options = SparkTableStorageFormat.DEFAULT_RAW
        database_location = db_info["db_raw_path"]

        logger.info(
            "m=__main__, msg=Creating database in Spark Metastore if not exists..."
        )
        metastore_service.create_database(database_name)

        s3_loader.load_full_table(
            df=df,
            database_name=database_name,
            table_name=endpoint_name,
            format_options=format_options,
            database_location=database_location,
        )

        spark_metastore_loader.update_metastore(
            df, database_name, endpoint_name, format_options, database_location
        )
