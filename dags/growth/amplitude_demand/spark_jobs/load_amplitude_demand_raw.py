import json
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from pyspark.sql.functions import lit

from bietlejuice.base.api import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService


JOB_NAME = "load_amplitude_demand_raw"

# Timeout between retries in seconds.
BACKOFF_FACTOR = 5
# Maximum number of retries for errors.
MAX_RETRIES = 5

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

    source_path = source.split('_')[0]

    dt = datetime.strptime(execution_date, "%Y-%m-%d")

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    all_keys = json.loads(dbutils.secrets.get("quintoandar", APIEnum.AMPLITUDE))

    key = [secret for secret in all_keys if secret['app_id'] == 170698][0]
    
    config_service = ConfigurationService(source)
    custom_records_per_file = config_service.get_config("custom_records_per_file")
    partition_cols = config_service.get_config("raw_partition_cols")
    table_name = config_service.get_config("table_name")
    transient_location = config_service.get_config("transient_location")
    transient_data_schema = config_service.get_config("transient_data_schema")
    transient_expected_cols = config_service.get_config("transient_expected_cols")

    spark_client = SparkClient()
    spark_context = spark_client.conn.sparkContext
    dataframe_service = SparkDataFrameService()

    db_info = DatalakeMetastoreService.get_db_info(environment, source_path, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_service.create_database(database_name)

    logger.info(
        f'''msg=initiating data processing, parameters
            environment = {environment}, datalake_bucket = {datalake_bucket},
            source = {source}, execution_date = {execution_date}, source_path = {source_path}
            database_name = {database_name}, database_location = {database_location}
        '''
    )

    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    s3_loader = S3Loader()

    transient_path = transient_location + f'170698/170698_{execution_date}_*/'

    logger.info(
        f'msg=starting events processing, app_id={key["app_id"]}, app_name={key["app_name"]}, path={transient_path}'
    )

    try:
        
        df = spark_client.conn.read.json(transient_path,  schema=transient_data_schema)

        if not(df.isEmpty()):
            logger.info(f'msg= events received from App ID {key["app_id"]} for this day.')

            df = (
                dataframe_service.input(df)
                .format_column_names()
                .convert_struct_type_to_json()
                .create_columns_from_dict({'app': key["app_id"]})
                .create_year_month_day_columns_from_dataframe_column(
                    "server_upload_time"
                )
                .output()
            )

            """
            TO-DO: Schema Compatibility between API data schema and Amplitude Pull Export data schema

            Creating two NULL columns that doesn't exists in Pull Export data.
                1. data_type
                2. insert_id
            """
            
            missing_cols = [col for col in transient_expected_cols if col not in df.columns]
            for col in missing_cols:

                df = df.withColumn(col, lit(None))
            
            df = df.select(transient_expected_cols)            

            df = df.na.drop(subset=partition_cols)

            s3_loader.load_df(
                df=df,
                s3_path=f"{database_location}{table_name}",
                format_options=format_options,
                partitions=partition_cols,
                max_records_per_file=custom_records_per_file,
                optimize_dataframe=False,
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
                database_name, table_name, df, partition_cols, parallelism=8
            )

        else:
            logger.info(f'msg=no events received from App ID {key["app_id"]} for this day.')

    except Exception as error:
        logger.info(f"msg=fail to get events from {dt}, cause={error}")
