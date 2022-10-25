import json
from argparse import ArgumentParser

from quintoandar_facebook_api_client.clients import FacebookClient
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.api import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkDataFrameService
from bietlejuice.base.spark import SparkTableStorageFormat, BaseDBUtils
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_casa_mineira_facebook_insights_raw"

logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("load_start_date", help="time_range start date in str format")
    parser.add_argument("load_end_date", help="time_range end date in str format")
    parser.add_argument("table_name")

    args = parser.parse_args()
    env = args.env
    source = args.source
    datalake_bucket = args.datalake_bucket
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date
    table_name = args.table_name

    config_service = ConfigurationService(source)
    accounts = config_service.get_config("accounts")[table_name]
    fields = config_service.get_config("fields")[table_name]
    breakdowns = config_service.get_config("breakdowns")[table_name]
    raw_partition_cols = config_service.get_config("raw_partition_cols")

    logger.info(
        f"""m=__main__, env={env}, source={source},
        datalake_bucket={datalake_bucket}, load_start_date={load_start_date}, load_end_date={load_end_date},
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
        date_start=load_start_date,
        date_stop=load_end_date,
        accounts=accounts,
        fields=fields,
        breakdowns=breakdowns,
    )

    if len(client_response):

        spark_client = SparkClient()
        df = spark_client.create_dataframe(client_response)

        df = (
            SparkDataFrameService()
            .input(df)
            .create_year_month_day_columns_from_dataframe_column("date_start")
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
            f"""m=__main__, load_start_date={load_start_date}, load_end_date={load_end_date}, table_name={table_name},
            accounts: {accounts}, msg=No data returned from API."""
        )
