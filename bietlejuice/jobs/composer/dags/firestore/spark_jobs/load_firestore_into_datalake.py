import json
import logging
from argparse import ArgumentParser
from datetime import datetime, timedelta
from pyspark.sql.types import StringType

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.base.db import DatabaseEnum, DatalakeMetastoreService
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import FirestoreConsumer
from bietlejuice.jobs.composer.loaders import S3Loader
from bietlejuice.jobs.composer.base.spark.spark_dataframe_service import (
    SparkDataFrameService,
)
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService


JOB_NAME = "load_firestore_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    # Get arguments passed by Airflow task
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("execution_date")
    parser.add_argument("table_name")
    parser.add_argument("date_field")

    args = parser.parse_args()

    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    execution_date = args.execution_date
    table_name = args.table_name
    date_field = args.date_field

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
    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    loader = S3Loader(spark_metastore_service)

    # Creates query filter
    start_date = datetime.strptime(execution_date, "%Y-%m-%d")
    end_date = start_date + timedelta(days=1)
    query = {
        "where": [
            {"field": date_field, "op": ">=", "value": start_date},
            {"field": date_field, "op": "<", "value": end_date},
        ]
    }

    # Retrieves data from Firestore, converting struct and array data types to json
    df = firestore_consumer.get_data_from_query(table_name=table_name, query=query)
    df = (
        SparkDataFrameService()
        .input(df)
        .convert_array_type_to_json()
        .convert_struct_type_to_json()
        .create_year_month_day_columns_from_dataframe_column(date_field)
        .output()
    )

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

    # Loads data into S3 incrementally
    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    spark_metastore_service.create_database(database_name)

    loader.load_incremental_table(
        df=df,
        database_name=database_name,
        table_name=table_name,
        format_options=SparkTableStorageFormat.DEFAULT_RAW,
        database_location=db_info["db_raw_path"],
        partition_cols=partition_cols,
        schema_merging=True,
    )

    spark_metastore_service.create_new_partitions_from_df(
        database_name=database_name,
        table_name=table_name,
        df=df,
        partition_cols=partition_cols,
    )

    spark_metastore_service.refresh_table(database_name, table_name)
