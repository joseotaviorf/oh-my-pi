import json

from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger
from quintoandar_criteo_api_client.clients import CriteoClient

from bietlejuice.jobs.composer.clients.db_clients import SparkClient

from bietlejuice.jobs.composer.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.api import APIEnum
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

JOB_NAME = "load_casa_mineira_criteo_campaigns_raw"

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
    table_name = config_service.get_config("table_name")
    raw_partition_cols = config_service.get_config("raw_partition_cols")
    request_headers = config_service.get_config("request_headers")
    request_body = config_service.get_config("request_body")
    request_body["startDate"] = request_body["endDate"] = execution_date

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    credentials_str = dbutils.secrets.get(
        scope="quintoandar", key=APIEnum.CRITEO_CASA_MINEIRA
    )
    credentials = json.loads(credentials_str)

    criteo_client = CriteoClient(
        client_id=credentials["client_id"], client_secret=credentials["client_secret"]
    )
    api_response = criteo_client.get_data(request_body, request_headers)

    if api_response:
        spark_client = SparkClient()
        df = spark_client.create_dataframe(api_response)
        df = df.withColumnRenamed("Day", "AttributionDate")
        dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
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
