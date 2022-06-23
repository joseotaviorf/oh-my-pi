import json
import logging
from argparse import ArgumentParser
from pyspark.sql.functions import unix_timestamp, to_timestamp, to_date

from quintoandar_logger import QuintoAndarLogger
from quintoandar_twilio_flex_insights_api_client.clients import TwilioFlexInsightsClient
from quintoandar_twilio_flex_insights_api_client.consumers import CONSUMERS
from quintoandar_twilio_flex_insights_api_client.constants.endpoint_enum import (
    EndpointEnum,
)

from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader
from bietlejuice.jobs.composer.base.api.api_enum import APIEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.jobs.composer.formatters import StringFormatter
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_incremental_data_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("context", help="name of the context")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    context = args.context

    logger.info(
        f"""
            m={JOB_NAME}, environment={environment}, datalake_bucket={datalake_bucket},
            source={source}, context={context}, msg=print spark jobs args"
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    json_credentials = dbutils.secrets.get(
        scope=DATABRICKS_SCOPE, key=APIEnum.TWILIO_FLEX_INSIGHTS
    )

    credentials = json.loads(json_credentials)
    twilio_flex_insights_client = TwilioFlexInsightsClient(
        {"email": credentials["email"], "pwd": credentials["pwd"]}
    )
    consumer = CONSUMERS["TwilioFlexInsights"](
        EndpointEnum.REPORTS_CONSUMER.value, client=twilio_flex_insights_client
    )

    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    s3_loader = S3Loader()

    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, source, datalake_bucket
    )
    database_name = datalake_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = datalake_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)

    config_service = ConfigurationService(context)
    partition_cols = config_service.get_config("partition_cols")

    for table_name, table_config in config_service.get_config(
        "tables_configurations"
    ).items():
        workspace_id = table_config["workspace_id"]
        object_id = table_config["object_id"]
        column_create_date = table_config["column_create_date"]

        consumer.client.refresh_token()

        uri = consumer.get_report_link(workspace_id, object_id)
        response = consumer.sync(uri).split("\r\n")
        response = [tuple(row.replace('"', "").split(",")) for row in response]
        schema = [
            StringFormatter.set_snake_case(column_name) for column_name in response[0]
        ]
        api_response = response[1:-1]

        if api_response:

            df = spark_client.create_dataframe(data=api_response, schema=schema)
            df = df.withColumn(
                column_create_date,
                to_date(to_timestamp(unix_timestamp(column_create_date, "MM/dd/yyyy"))),
            )
            df = (
                SparkDataFrameService()
                .input(df)
                .create_year_month_day_columns_from_dataframe_column(column_create_date)
                .output()
            )

            # loaders
            s3_loader.load_incremental_table(
                df=df,
                database_name=database_name,
                table_name=table_name,
                database_location=database_location,
                format_options=format_options,
                partition_cols=partition_cols,
            )
            spark_metastore_loader.update_metastore(
                df,
                database_name,
                table_name,
                format_options,
                database_location,
                partition_cols,
                force_recreate=False,
            )
            spark_metastore_service.create_new_partitions_from_df(
                database_name=database_name,
                table_name=table_name,
                df=df,
                partition_cols=partition_cols,
            )
        else:
            raise Exception(
                f"""m=__main__, table_name={table_name},
                msg=No data returned from API."""
            )

    consumer.client.close()
