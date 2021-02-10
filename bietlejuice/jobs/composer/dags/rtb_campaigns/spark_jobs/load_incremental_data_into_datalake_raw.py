import json
import logging

from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger
from quintoandar_rtb_api_client.clients import RTBClient

from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient

from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from pyspark.sql.types import StructType, StructField, StringType, DoubleType

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_incremental_data_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


schema = StructType(
    [
        StructField("subcampaign", StringType(), True),
        StructField("impsCount", DoubleType(), True),
        StructField("clicksCount", DoubleType(), True),
        StructField("campaignCost", DoubleType(), True),
        StructField("conversionsCount", DoubleType(), True),
        StructField("conversionsValue", DoubleType(), True),
        StructField("cr", DoubleType(), True),
        StructField("ctr", DoubleType(), True),
        StructField("roas", DoubleType(), True),
        StructField("subcampaignHash", StringType(), True),
        StructField("account_hash", StringType(), True),
        StructField("account_name", StringType(), True),
        StructField("account_currency", StringType(), True),
        StructField("account_status", StringType(), True),
        StructField("cost_attribution_date", StringType(), True),
    ]
)


def get_api_response(account, execution_date):
    client_id = account["client_id"]
    client_secret = account["client_secret"]
    rtb_client = RTBClient(
        client_id=client_id, client_secret=client_secret, execution_date=execution_date
    )
    try:
        api_response = rtb_client.get_data()
        for data in api_response:
            data["cost_attribution_date"] = data.pop("day")
            data["conversionsCount"] = float(data["conversionsCount"])
        return api_response
    except Exception as e:
        logger.error(f"m=get_api_response, msg={e}")


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("media", help="name of the media")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("account", help="account w/ id and secret for api call")
    parser.add_argument("execution_date", help="execution date in str format")

    args = parser.parse_args()

    logger.info(
        f"""
            m={JOB_NAME}, environment={args.environment}, source={args.source}, media={args.media},
            execution_date={args.execution_date}, datalake_bucket={args.datalake_bucket}, msg=print spark jobs args"
        """
    )

    environment = args.environment
    source = args.source
    media = args.media
    datalake_bucket = args.datalake_bucket
    account = json.loads(args.account)
    execution_date = args.execution_date
    partition_cols = ["year", "month", "day"]

    spark_client = SparkClient()
    api_response = get_api_response(account, execution_date)

    if api_response:
        df = spark_client.create_dataframe(api_response)
        dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
        df = df.coalesce(1)
        df = (
            SparkDataFrameService()
            .input(df)
            .create_year_month_day_columns_from_date(dt_execution)
            .output()
        )

        datalake_info = DatalakeMetastoreService.get_db_info(
            environment, source, datalake_bucket
        )
        spark_metastore_service = SparkMetastoreService(spark_client)
        database_name = datalake_info["db_raw_databricks"]
        spark_metastore_service.create_database(database_name)

        database_location = datalake_info["db_raw_path"]
        format_options = SparkTableStorageFormat.DEFAULT_RAW
        table_name = media

        # loaders
        s3_loader = S3Loader()
        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            partitions=partition_cols,
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
        spark_metastore_service.refresh_table(database_name, table_name)
