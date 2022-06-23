import json
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_facebook_api_client.clients import FacebookClient
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.api import APIEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat, BaseDBUtils
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_casa_mineira_facebook_insights_raw"

logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("execution_date")
    parser.add_argument("table_name")

    args = parser.parse_args()
    env = args.env
    source = args.source
    datalake_bucket = args.datalake_bucket
    execution_date = args.execution_date
    table_name = args.table_name

    config_service = ConfigurationService(source)
    accounts = config_service.get_config("accounts")[table_name]
    fields = config_service.get_config("fields")[table_name]
    breakdowns = config_service.get_config("breakdowns")[table_name]
    raw_partition_cols = config_service.get_config("raw_partition_cols")

    logger.info(
        f"""m=__main__, env={env}, source={source},
        datalake_bucket={datalake_bucket}, execution_date={execution_date},
        table_name={table_name}, msg=Starting spark job..."""
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    auth = json.loads(
        dbutils.secrets.get(scope="quintoandar", key=APIEnum.FACEBOOK_CASA_MINEIRA)
    )

    fb_client = FacebookClient(auth["access_token"])
    client_response = fb_client.get_data(
        date=execution_date, accounts=accounts, fields=fields, breakdowns=breakdowns
    )

    if len(client_response):

        spark_client = SparkClient()
        df = spark_client.create_dataframe(client_response)

        dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
        df = (
            SparkDataFrameService()
            .input(df)
            .create_year_month_day_columns_from_date(dt_execution)
            .output()
        )

        datalake_info = DatalakeMetastoreService.get_db_info(
            env, source, datalake_bucket
        )
        spark_metastore_service = SparkMetastoreService(spark_client)
        database_name = datalake_info["db_raw_databricks"]
        spark_metastore_service.create_database(database_name)

        database_location = datalake_info["db_raw_path"]
        format_options = SparkTableStorageFormat.DEFAULT_RAW

        # loaders
        s3_loader = S3Loader()
        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            partitions=raw_partition_cols,
        )
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
        logger.warning(
            f"""m=__main__, execution_date={execution_date}, table_name={table_name},
            accounts: {accounts}, msg=No data returned from API."""
        )
