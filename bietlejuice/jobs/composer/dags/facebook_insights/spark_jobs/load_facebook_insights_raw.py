import json
import logging

from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger
from quintoandar_facebook_api_client.clients import FacebookClient

from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat, BaseDBUtils
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.base.api import APIEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader

JOB_NAME = "load_incremental_data_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("context", help="name of the context")
    parser.add_argument("execution_date", help="execution date in str format")
    parser.add_argument("table_name", help="granularity columns")

    args = parser.parse_args()
    env = args.env
    source = args.source
    context = args.context
    datalake_bucket = args.datalake_bucket
    execution_date = args.execution_date
    table_name = args.table_name

    config_service = ConfigurationService(context)
    accounts = config_service.get_config("accounts")[table_name]
    fields = config_service.get_config("fields")[table_name]
    breakdowns = config_service.get_config("breakdowns")[table_name]
    raw_partition_cols = config_service.get_config("raw_partition_cols")

    logger.info(
        f"""m=__main__, env={env}, source={source}, context={context},
        datalake_bucket={datalake_bucket}, execution_date={execution_date},
        table_name={table_name}, msg=Starting spark job..."""
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    configs = json.loads(dbutils.secrets.get(scope="quintoandar", key=APIEnum.FACEBOOK))
    auth = configs.pop("auth")

    configs["date"] = execution_date
    configs["accounts"] = accounts
    configs["fields"] = fields
    configs["breakdowns"] = breakdowns

    fb_client = FacebookClient(auth["access_token"])
    client_response = fb_client.get_data(**configs)

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
        spark_metastore_service.refresh_table(database_name, table_name)

    else:
        logger.warning(
            f"""m=__main__, execution_date={execution_date}, table_name={table_name},
            accounts: {accounts}, msg=No data returned from API."""
        )
