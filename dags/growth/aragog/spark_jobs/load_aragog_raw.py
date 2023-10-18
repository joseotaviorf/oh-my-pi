from argparse import ArgumentParser
from quintoandar_logger import QuintoAndarLogger
import datetime as dt

from bietlejuice.base.db import DatalakeMetastoreMapping
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat, SparkDataFrameService
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService
from pyspark.sql.functions import col


JOB_NAME = "load_aragog_raw"

logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env")
    parser.add_argument("datalake_bucket", type=str, help="target bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("crawler")
    parser.add_argument("table")

    args = parser.parse_args()

    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    crawler = args.crawler
    table = args.table

    config_service = ConfigurationService(source)
    datalake_metastore_mapper = DatalakeMetastoreMapping(source=source , bucket=datalake_bucket)
    raw_partition_cols = config_service.get_config("raw_partition_cols")
    bucket_path = config_service.get_config("bucket_path")
    file_path = f"{bucket_path}/{crawler}/{table}.json"

    logger.info(
    f"""m={JOB_NAME}, environment={env}, source={source}, datalake_bucket={datalake_bucket},
    table_name={table_name}, msg=Starting spark job..."""
    )

    spark_client = SparkClient()
    s3_loader = S3Loader()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    df_service = SparkDataFrameService()

    db_info = datalake_metastore_mapper.get_all_datalake_info()
    database_name = db_info["db_raw_name"]
    database_location = db_info["db_raw_path"]

    base_dbutils = BaseDBUtils()

    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    spark_metastore_service.create_database(database_name)

    logger.info(f"""m={JOB_NAME}, source_bucket={bucket_path}, table_name={table_name}, msg=Getting data from bucket...""")

    df = None

    try:
        df = spark_client.conn.read.json(file_path)

        if df is not None:
            
            df = df.withColumn('accessed_at', col('metadata.accessed_at'))

            df = (df_service
                    .input(df)
                    .create_year_month_day_columns_from_dataframe_column("accessed_at")
                    .format_column_names()
                    .convert_struct_type_to_json()
                    .output()
                )

            logger.info(f"""m={JOB_NAME}, source_bucket={bucket_path}, table_name={table_name}, msg=Loading raw data on bucket...""")
            s3_loader.load_df(
                df=df,
                format_options=SparkTableStorageFormat.DEFAULT_RAW,
                s3_path=f"{database_location}{table_name}",
                partitions=raw_partition_cols,
                compression="gzip"
            )
            
            
            logger.info(f"""m={JOB_NAME}, source_bucket={bucket_path}, table_name={table_name}, msg=Update metastore...""")
            spark_metastore_loader.update_metastore(
                df=df,
                database_name=database_name,
                table_name=table_name,
                format_options=SparkTableStorageFormat.DEFAULT_RAW,
                database_location=database_location,
                partitions=raw_partition_cols,
            )

            spark_metastore_service.create_new_partitions_from_df(
                df=df,
                database_name=database_name,
                table_name=table_name,
                partition_cols=raw_partition_cols,
            ) 

        else:
            logger.info(f"""m={JOB_NAME}, source_bucket={bucket_path}, table_name={table_name}, msg=These dataframe is empty...""")
    
    except Exception as e:
        logger.warning(f"""m={JOB_NAME}, table_name={table_name}, msg={e}.""")