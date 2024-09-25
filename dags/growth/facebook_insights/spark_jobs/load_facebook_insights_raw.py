import json
import logging

from argparse import ArgumentParser
from pyspark.sql.functions import udf

from quintoandar_logger import QuintoAndarLogger
from quintoandar_facebook_api_client.clients import FacebookClient

from bietlejuice.formatters import StringFormatter
from bietlejuice.base.spark import SparkTableStorageFormat, BaseDBUtils
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.base.api import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkDataFrameService
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService

from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader

JOB_NAME = "load_incremental_data_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("load_start_date", help="time_range start date in str format")
    parser.add_argument("load_end_date", help="time_range end date in str format")
    parser.add_argument("manual_accounts", help="list of accounts")
    parser.add_argument("table_name", help="granularity columns")

    args = parser.parse_args()
    env = args.env
    source = args.source
    datalake_bucket = args.datalake_bucket
    table_name = args.table_name
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date
    manual_accounts = args.manual_accounts

    config_service = ConfigurationService(source)
    accounts = config_service.get_config("accounts")[table_name]
    fields = config_service.get_config("fields")[table_name]
    breakdowns = config_service.get_config("breakdowns")[table_name]
    raw_partition_cols = config_service.get_config("raw_partition_cols")[table_name]

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    configs = json.loads(dbutils.secrets.get(scope="quintoandar", key=APIEnum.FACEBOOK))
    auth = configs.pop("auth")

    # for now, only facebook_insights account can be reprocessed by manual inputed accounts
    if table_name == "facebook_insights" and manual_accounts:
        try:
            manual_accounts = json.loads(manual_accounts.replace("'", '"'))
        except ValueError:
            raise ValueError("m=get_accounts_param, msg=Enter a valid json string")
        else:
            if "facebook_insights" in manual_accounts:
                manual_accounts_list = manual_accounts.get(table_name)
                if isinstance(manual_accounts_list, list):
                    accounts = manual_accounts_list
                else:
                    raise Exception(
                        f"m=get_accounts_param, msg=Accounts inside {table_name} key should be a list"
                    )
            else:
                raise Exception(
                    "m=get_accounts_param, msg=Key should be facebook_insights"
                )

    logger.info(
        f"""m=__main__, env={env}, source={source}, datalake_bucket={datalake_bucket},
            load_start_date={load_start_date}, load_end_date={load_end_date},
            table_name={table_name}, accounts={accounts}, msg=Starting spark job..."""
    )

    configs["date_start"] = load_start_date
    configs["date_stop"] = load_end_date
    configs["accounts"] = accounts
    configs["fields"] = fields
    configs["breakdowns"] = breakdowns

    fb_client = FacebookClient(auth["access_token"])
    client_response = fb_client.get_data(**configs)

    if len(client_response):

        spark_client = SparkClient()
        df = spark_client.create_dataframe(client_response)

        df = (
            SparkDataFrameService()
            .input(df)
            .create_year_month_day_columns_from_dataframe_column("date_start")
            .output()
        )

        if "account_name" in df.columns:
            df = df.withColumn(
                "account_name_snake_case",
                udf(StringFormatter.set_alphanumeric_snake_case)(df.account_name),
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
            f"""m=__main__, load_start_date={load_start_date}, load_end_date={load_end_date}, table_name={table_name},
                accounts: {accounts}, msg=No data returned from API."""
        )
