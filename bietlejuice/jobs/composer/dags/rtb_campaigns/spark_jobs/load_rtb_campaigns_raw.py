import json

from argparse import ArgumentParser
from datetime import datetime
from rtbhouse_sdk.reports_api import Conversions, ReportsApiSession

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.clients.db_clients import SparkClient

from bietlejuice.jobs.composer.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.api import APIEnum
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

JOB_NAME = "load_rtb_campaigns_raw"
logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("execution_date")

    args = parser.parse_args()
    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    execution_date = args.execution_date

    logger.info(
        f"""
            m={JOB_NAME}, environment={environment},
            datalake_bucket={datalake_bucket}, source={source},
            execution_date={execution_date}, msg=Starting spark job..."
        """
    )

    config_service = ConfigurationService(source)
    raw_partition_cols = config_service.get_config("raw_partition_cols")
    table_name = config_service.get_config("table_name")
    account_hashes = config_service.get_config("account_hashes")
    metrics = config_service.get_config("metrics")
    group_by = config_service.get_config("group_by")
    schema = config_service.get_config("schema")

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    credentials_str = dbutils.secrets.get(scope="quintoandar", key=APIEnum.RTB)
    credentials = json.loads(credentials_str)

    rtb_client = ReportsApiSession(
        username=credentials["client_id"], password=credentials["client_secret"]
    )

    stats = []
    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")

    for account_hash in account_hashes:
        stats_response = rtb_client.get_rtb_stats(
            adv_hash=account_hash,
            day_from=dt_execution,
            day_to=dt_execution,
            group_by=group_by,
            metrics=metrics,
            count_convention=Conversions.ATTRIBUTED_POST_CLICK,
        )
        if stats_response:
            account_details = rtb_client.get_advertiser(adv_hash=account_hash)
            # Appends string "account" into all keys from account_details dict:
            account_details = {
                "account" + k[0].upper() + k[1:]: v for k, v in account_details.items()
            }
            stats_response = list(
                map(lambda record: {**record, **account_details}, stats_response)
            )
            stats += stats_response
        else:
            logger.warn(
                f"m=__main__, msg=No data was received from account with ID {account_hash}."
            )
    if stats:
        spark_client = SparkClient()
        df = spark_client.create_dataframe(stats, schema=schema)
        df = df.withColumnRenamed("day", "attributionDate")
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

        # loaders
        s3_loader = S3Loader()
        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            partitions=raw_partition_cols,
        )
        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
        spark_metastore_loader.update_metastore(
            df,
            database_name,
            table_name,
            format_options,
            database_location,
            raw_partition_cols,
            force_recreate=False,
        )
        spark_metastore_service.create_new_partitions_from_df(
            database_name=database_name,
            table_name=table_name,
            df=df,
            partition_cols=raw_partition_cols,
        )
    else:
        logger.warn(f"m=__main__, msg=All accounts returned no data.")
