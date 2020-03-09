import json
import logging
from argparse import ArgumentParser
from pyspark.sql.types import StringType
from pyspark.sql.functions import coalesce

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.jobs.composer.base.athena import TableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import AthenaClient, SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import FirestoreConsumer
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.base.spark.spark_dataframe_service import (
    SparkDataFrameService,
)
from bietlejuice.jobs.composer.services.metastore_services import (
    AthenaMetastoreService,
    SparkMetastoreService,
)


JOB_NAME = "load_firestore_historical_data"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    # ----------------------------------------------------------------
    # LOADS DATA INTO DATALAKE RAW
    # ----------------------------------------------------------------

    # Get arguments passed by Airflow task
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("storage")

    args = parser.parse_args()

    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    storage = args.storage

    # Sets Firestore consumer
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    connection_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.FIRESTORE
    )
    connection = json.loads(connection_json)
    firestore_consumer = FirestoreConsumer(connection)

    # Sets S3 Loader
    athena_metastore_service = AthenaMetastoreService(AthenaClient())
    spark_metastore_service = SparkMetastoreService(SparkClient())
    loader = S3Loader(spark_metastore_service)

    # DB Info
    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    db_databricks = db_info["db_{}_databricks".format(storage)]
    db_athena = db_info["db_{}_athena".format(storage)]
    db_path = db_info["db_{}_path".format(storage)]

    # Retrieves data from Firestore, converting struct and array data types to json
    df_original = firestore_consumer.get_data_from_table(table_name=table_name)

    # Creates new column considering 'createdDate' when 'lastSentDate' doesn't exist.
    # This column will be used to partition the table
    df_original = df_original.withColumn(
        "data_coalesce",
        coalesce(df_original["lastSentDate"], df_original["createdDate"]),
    )

    # Discarding some cases with garbage on the date column
    df_original = df_original.filter("data_coalesce > '2017-01-01'")

    # Converts array and struct data types to json-like strings.
    # Creates year-month-day columns based on the date column.
    df = (
        SparkDataFrameService()
        .input(df_original)
        .optimize_partition(45000)
        .convert_array_type_to_json()
        .convert_struct_type_to_json()
        .create_year_month_day_columns_from_dataframe_column("data_coalesce")
        .output()
    )

    # Drops new date column, since we already have the partition columns
    df = df.drop("data_coalesce")

    # Converts all fields to string (except for the partition columns)
    partition_cols = ["year", "month", "day"]
    for field in df.schema.fields:
        if (not isinstance(field.dataType, StringType)) and (
            field.name not in partition_cols
        ):
            logger.info(
                "m=load_data_to_raw, msg=converting field {} to string".format(
                    field.name
                )
            )
            df = df.withColumn(field.name, df[field.name].cast("string"))

    # Loads data into S3
    spark_metastore_service.create_database(db_databricks)

    loader.load_full_table(
        df=df,
        database_name=db_databricks,
        table_name=table_name,
        format=SparkTableStorageFormat.DEFAULT_RAW,
        database_location=db_info["db_raw_path"],
        partitions=partition_cols,
    )

    spark_metastore_service.create_new_partitions_from_df(
        database_name=db_databricks,
        table_name=table_name,
        df=df,
        partition_cols=partition_cols,
    )

    spark_metastore_service.refresh_table(db_databricks, table_name)

    # ----------------------------------------------------------------
    # CREATES ATHENA EXTERNAL TABLE
    # ----------------------------------------------------------------
    logger.info(
        "m=__main__, table_name= {}, msg=Creating {} external table...".format(
            table_name, storage
        )
    )
    table_schema = spark_metastore_service.get_table_schema(db_databricks, table_name)
    partition_cols = ["year", "month", "day"]
    athena_metastore_service.create_database(db_athena)
    athena_metastore_service.drop_table(db_athena, table_name)
    athena_metastore_service.create_external_table(
        database_name=db_athena,
        table_name=table_name,
        table_location=db_path + table_name,
        table_schema=table_schema,
        partition_cols=partition_cols,
        format_options=TableStorageFormat.get_storage(storage),
    )
    athena_metastore_service.repair_table_partitions(db_athena, table_name)

    logger.info("m=__main__, msg=External table created successfully.")
