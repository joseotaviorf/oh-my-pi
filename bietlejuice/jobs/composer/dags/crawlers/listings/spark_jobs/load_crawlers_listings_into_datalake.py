import logging
import re
from argparse import ArgumentParser
from datetime import datetime

from pyspark.sql.functions import lit
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.s3_consumer import S3Consumer
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_crawler_listings_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def replace_for_array_schema(schema_list: list, key: str) -> list:
    """
    Check if the given field already exists in the new_schema list as a string
    and replace it for the key:array<string> schema.

    When an element of the struct is a list this function will search inside the list for
    any appearence of this element that is not <element_name>:array<string>. For example,
    the field amenities can come as a single string (amenities<string>) and also as a list
    of strings (amenities:array<string>). The funtion will delete the single string schema
    and replace for the array schema.

    :param schema_list: List with the struct elements.
    :param key: Element name that will be searched
    :return new_schema_list: New list with the struct element replaced or not.
    """
    string_to_replace = f"{key}:array<string>"
    string_to_search = f"{key}:string"
    r = re.compile(string_to_search)
    has_match = list(filter(lambda item: r.search(item), (schema_list)))

    if has_match != [] and string_to_replace not in schema_list:
        string_to_remove_index = schema_list.index(has_match[0])
        schema_list[string_to_remove_index] = string_to_replace

    return schema_list


def build_new_schema_list(df_rows: list, struct_column_name: str) -> str:
    """
    Returns a string that defines the schema for the given struct column.

    :param df_rows: listof rows (A row is a pyspark.DataFrame.Row object)
    :param struct_column_name: String used to indicate the column that will be accessed.
    :return schema_string: The string that will be used to cast the Dataframe column.
    """
    new_schema = []
    for row in df_rows:
        row_as_dict = row.asDict(recursive=True)
        house_info_column = row_as_dict[struct_column_name]
        for key, value in house_info_column.items():
            if type(value) == list:
                element = f"{key}:array<string>"
                replace_for_array_schema(new_schema, key)
            else:
                element = f"{key}:string"
            r = re.compile(key)
            has_match = list(filter(lambda item: r.search(item), new_schema))
            if has_match == []:
                new_schema.append(element)

    str_new_schema = f"struct<{','.join(new_schema)}>"

    return str_new_schema


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("context")
    parser.add_argument("table_name")
    parser.add_argument("origin", type=str, help="Name of crawled source")
    parser.add_argument("execution_date")

    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    context = args.context
    table_name = args.table_name
    origin = args.origin
    execution_date_str = args.execution_date

    config_service = ConfigurationService(
        source, intermediate_path=f"{source}/{context}/spark_jobs"
    )
    source_root_path = config_service.get_config("root_path")
    job_extra_args = config_service.get_config("job_extra_args")
    consumer_extra_args = job_extra_args.get("consumer")
    custom_records_per_file = job_extra_args.get("custom_records_per_file")
    partitions = config_service.get_config("partition_cols")

    logger.info(
        f"""
                m=__main__, environment={environment}, source={source}, context = {context},datalake_bucket={datalake_bucket}, origin={origin},
                source_root_path={source_root_path}, table_name={table_name}, execution_date={execution_date_str} msg=Starting spark job...
        """
    )

    execution_date = datetime.strptime(execution_date_str, "%Y-%m-%d")

    # Initializing clients
    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)
    path = (
        source_root_path
        + f"origin={origin}/year={execution_date.year}/month={execution_date.month}/day={execution_date.day}/"
    )
    df = s3_consumer.get_data_from_file(path=path, **consumer_extra_args)
    df = (
        df.withColumn("year", lit(execution_date.year))
        .withColumn("month", lit(execution_date.month))
        .withColumn("day", lit(execution_date.day))
    )

    if origin == "emcasa":
        str_schema = "struct<typename:string,itbi:string,propertydeed:string,propertyregistration:string>"
        df = df.withColumn("metadata", df["metadata"].cast(str_schema))

    if origin == "loft":
        rows = df.collect()
        new_schema_string = build_new_schema_list(rows, "house_info")
        df = df.withColumn("house_info", df["house_info"].cast(new_schema_string))

    db_info = DatalakeMetastoreService.get_db_info(
        environment, f"{source}_{context}", datalake_bucket
    )
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)

    s3_loader = S3Loader()

    s3_loader.load_df(
        df=df,
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
        partitions=partitions,
        max_records_per_file=custom_records_per_file.get(
            origin, s3_loader.MAX_RECORDS_PER_FILE
        ),
    )

    spark_metastore_loader.update_metastore(
        df,
        database_name,
        table_name,
        format_options,
        database_location,
        partitions,
        force_recreate=False,
    )

    spark_metastore_service.create_new_partitions_from_df(
        database_name=database_name,
        table_name=table_name,
        df=df,
        partition_cols=partitions,
    )
