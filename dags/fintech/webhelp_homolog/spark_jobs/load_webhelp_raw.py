import json
import logging
from argparse import ArgumentParser

from pyspark.sql.functions import current_timestamp, lit
from pyspark.sql.utils import AnalysisException
from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.pipeline import LayerEnum

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (SparkDataFrameService,
                                    SparkTableStorageFormat)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.pipeline import FullTableLoaderPipeline
from bietlejuice.base.spark import BaseDBUtils


JOB_NAME = "load_webhelp_raw"


logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_azure_credentials():
    DATABRICKS_SCOPE = "quintoandar"
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        global dbutils
        dbutils = base_dbutils.get_dbutils()

    json_credentials = dbutils.secrets.get(
        scope=DATABRICKS_SCOPE, key="AZURE_WEBHELP"
    )
    credentials = json.loads(json_credentials)

    return credentials['storage_account_name'], credentials['storage_account_access_key']


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("azure_container_name", help="azure container name")
    parser.add_argument("azure_sub_folder", help="azure sub folder")
    parser.add_argument("date_to_ingest", help="Date to be used in filtering the files. Format: '%Y-%m-%d'",)
    parser.add_argument("table_name", help="table name")
    parser.add_argument("format", help="object format")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    azure_container_name = args.azure_container_name
    azure_sub_folder = json.loads(args.azure_sub_folder)
    date_to_ingest = args.date_to_ingest
    table_name = args.table_name
    format = args.format

    logger.info(
        f"""m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
        azure_container_name={azure_container_name}, date_to_ingest={date_to_ingest}, table_name={table_name}.
        msg=Starting spark job...
        """)

    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)
    s3_loader = S3Loader()

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.PARQUET

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    container_name = "lake-quinto-andar-sftp"
    azure_account_name, azure_account_key = get_azure_credentials()
    spark.conf.set("fs.azure.account.key." + azure_account_name + ".blob.core.windows.net", azure_account_key)

    azure_table_name = table_name.upper()

    df_schema = spark.read.parquet(f"wasbs://{container_name}@{azure_account_name}.blob.core.windows.net/EXPORTACOES/ATENDIMENTO/{azure_table_name}/").schema
    df_schema.add("subfolder", "string")
    logger.info(
        f"""m=__main__, msg=Dataframe Schema: {df_schema}"""
    )
    final_df = spark_client.create_dataframe([], df_schema)

    for subfolder in azure_sub_folder:

        blob_storage_path = f"wasbs://{azure_container_name}@{azure_account_name}.blob.core.windows.net/EXPORTACOES/{subfolder}"

        logger.info(
            f"""m=__main__, msg=File name to be processed: {blob_storage_path}"""
        )

        try:
            df = s3_consumer.get_data_from_file(path=f"{blob_storage_path}/{azure_table_name}/", format=format)
        except AnalysisException as error:
            logger.warning(
                f"""
                m=__main__, msg=No data found for {blob_storage_path}, table_name={azure_table_name}.

                Exception: {error}
                """
            )
            raise error
        df = df.withColumn("subfolder", lit(subfolder))
        final_df = final_df.union(df)

    # Rename columns to lowercase
    columns = final_df.columns
    for col in columns:
        final_df = final_df.withColumnRenamed(col, col.lower())

    # Add ts_load columns
    final_df = final_df.withColumn("ts_load", current_timestamp())

    final_df = (
        SparkDataFrameService()
        .input(final_df)
        .output()
    )
    print("Dataframe sample:\n")
    final_df.show(5)

    FullTableLoaderPipeline(
        database_name=database_name,
        table_name=table_name,
        database_location=database_location,
        layer=LayerEnum.RAW,
        query=None
    ).load_and_register(final_df, format_options)
