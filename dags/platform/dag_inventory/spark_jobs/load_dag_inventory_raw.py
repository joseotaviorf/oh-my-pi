"""
This spark job reads the data previously fetched from DagBags and saved to S3, enriches it, and saves it to datalake_dag_inventory_raw.

This process has 5 steps:
1 - Read json from S3 as a dictionary
2 - Enrich dictionary
3 - Transform dictionary into a Spark DataFrame
4 - Enrich DataFrame
5 - Create table in Spark Metastore using the dataframe.

Steps 2 and 4 are separate because some enrichments are easier to be done before serializing, and some are more efficient after.
"""

import json
import logging
import re
from argparse import ArgumentParser
from datetime import datetime, timedelta
from multiprocessing.pool import ThreadPool

import boto3
import botocore
import pyspark.sql.functions as SF
from pyspark.sql import DataFrame, Row
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.base.spark.spark_metastore_helper import SparkMetastoreHelper
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import MetastoreServiceFactory

JOB_NAME = "load_dag_inventory_raw"
THREAD_NUMBER = 8
# TODO: Optimize file fetching so we can uncomment this
LAYERS_TO_FETCH_FILES = [
    # LayerEnum.CLEAN.value,
    # LayerEnum.ENRICH.value,
    # LayerEnum.DW.value,
    # LayerEnum.METRIC.value,
]

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
config_service = ConfigurationService("dag_inventory")


"""
Given the table name and execution date, finds the content fetched from DagBags and saved on S3, and returns it as a dictionary.
"""


def read_dag_bag_content(table_name: str, execution_date: datetime) -> dict:
    s3 = boto3.resource("s3")
    date_partitions = f"year={execution_date.year}/month={execution_date.month}/day={execution_date.day}"
    file_path = f"raw/dag_inventory/dag_bag_content/{table_name}/{date_partitions}/{table_name}.json"
    content_object = s3.Object(datalake_bucket, file_path)
    file_content = content_object.get()["Body"].read().decode("utf-8")
    return json.loads(file_content)


"""
Given a dictionary with table data fetched from DagBags, enriches it with complementary information from Spark Metastore.

For example, the dictionary data originally comes from the arguments passed to tasks that sync with hive metastore. However, in some cases
a single task is responsible for syncing all tables in the database, so table_name comes as null. For those cases, this function searches
for all tables in that database to fill this information.
"""


def enrich_table_dictionary_with_spark_metastore(content: dict) -> dict:
    mapping = []
    for row in content:
        try:
            spark_ms = SparkMetastoreHelper(
                row["bucket"],
                row["layer"],
                row["database"],
                row["table"],
                all_tables=row["table"] is None,
                transformation_grade=row.get("transformation_grade"),
            )
            spark_ms.validate_table_arguments()
            database_name, database_location = spark_ms.get_metastores_metadata()
            table_names = spark_ms.get_table_names()
            for table in table_names:
                mapping.append(
                    {
                        "dag": row["dag"],
                        "task": row["task"],
                        "files_location": f"{database_location}{table}",
                        "table": f"{database_name}.{table}",
                        "layer": row["layer"],
                        "bucket": row["bucket"],
                        "is_delta": row["is_delta"],
                    }
                )
        except Exception as error:
            logger.info(
                f"m=enrich_table_dictionary_with_spark_metastore, dag={row['dag']}, task={row['task']}, "
                f"layer={row['layer']}, database={row['database']}, table={row['table']}, "
                f"msg=Skipping row, error={error}"
            )
    return mapping


"""
Given the bucket and the file name as given by the S3 iterator, returns it in the appropriate format of the folder.
"""


def sanitize_file_name(bucket: str, file: str) -> str:
    if "dw" in bucket:
        file_sanitized = "/".join(file.split("/")[0:2])
    else:
        file_sanitized = "/".join(file.split("/")[0:3])

    return f"s3a://{bucket}/{file_sanitized}"


def fetch_partition_name(file_name):
    return re.sub("/part\-.*", "", file_name)


"""
Given the table and execution date, finds all files modified in that day, and returns a DataFrame with some metrics
associated with file size and quantity.
"""


def find_recently_modified_files_by_table(
    table_content: dict, execution_date: datetime
) -> list:
    bucket = table_content["files_location"].split("://")[1].split("/")[0]
    prefix = "/".join(table_content["files_location"].split("://")[1].split("/")[1:])
    previous_date = execution_date - timedelta(days=1)
    incremental_prefix = f"{prefix}/year={previous_date.year}/month={previous_date.month}/day={previous_date.day}"
    incremental_files = find_recently_modified_files_by_prefix(
        bucket, incremental_prefix, execution_date
    )
    if len(incremental_files) > 0:
        return incremental_files
    return find_recently_modified_files_by_prefix(bucket, prefix, execution_date)


"""
Given the bucket, layer and execution date, finds all files modified in that day, and returns a DataFrame with some metrics
associated with file size and quantity.
"""


def find_recently_modified_files_by_prefix(
    bucket: str, prefix: str, execution_date: datetime
) -> list:
    s3_client = boto3.client("s3")
    s3_paginator = s3_client.get_paginator("list_objects_v2")

    s3_iterator = s3_paginator.paginate(Bucket=bucket, Prefix=prefix)
    formatted_date = execution_date.strftime("%Y-%m-%d")
    objects = s3_iterator.search(
        f"Contents[?(to_string(LastModified)>='\"{formatted_date} 00:00:00+00:00\"'&&to_string(LastModified)<='\"{formatted_date} 23:59:59+00:00\"')].[Key,Size,LastModified]"
    )
    object_tuples = []
    try:
        for obj in objects:
            if obj is not None and obj[0].endswith(
                (".json", ".parquet", ".txt", ".csv")
            ):
                object_tuples.append(
                    (
                        sanitize_file_name(bucket, obj[0]),
                        fetch_partition_name(obj[0]),
                        obj[0],
                        obj[1],
                        obj[2],
                    )
                )
    except botocore.exceptions.ClientError as error:
        logging.error(f"Problem with prefix {prefix} on bucket {bucket}")
        if error.response["Error"]["Code"] == "AccessDenied":
            logging.error("Permission error. Skipping table.")
            return []
        raise error

    return object_tuples


"""""
Transforms a list of tuples containing, in order, file name and file size, into a DataFrame. It also adds file size and quantity
metrics.
"""


def create_file_metrics_data_frame(object_tuples: list) -> DataFrame:
    df = spark.createDataFrame(
        object_tuples,
        schema="table_name:string, partition_name:string, file_name:string, file_size_in_bytes:bigint, ts_modified: timestamp",
    )

    return df.groupBy(["table_name"]).agg(
        SF.countDistinct("partition_name").alias("qty_modified_partitions"),
        SF.countDistinct("file_name").alias("qty_modified_files"),
        SF.min("file_size_in_bytes").alias("min_file_size_in_bytes"),
        SF.percentile_approx("file_size_in_bytes", 0.25, SF.lit(1000000)).alias(
            "q25_size_in_bytes"
        ),
        SF.percentile_approx("file_size_in_bytes", 0.50, SF.lit(1000000)).alias(
            "q50_size_in_bytes"
        ),
        SF.percentile_approx("file_size_in_bytes", 0.75, SF.lit(1000000)).alias(
            "q75_size_in_bytes"
        ),
        SF.max("file_size_in_bytes").alias("max_file_size_in_bytes"),
        SF.avg("file_size_in_bytes").alias("avg_file_size_in_bytes"),
        SF.sum(SF.when(SF.col("file_size_in_bytes") < 1000000, 1).otherwise(0)).alias(
            "qty_smaller_than_1mb"
        ),
        SF.sum(
            SF.when(SF.col("file_size_in_bytes") > 1000000000, 1).otherwise(0)
        ).alias("qty_bigger_than_1gb"),
        SF.sum("file_size_in_bytes").alias("total_modified_files_size_in_bytes"),
    )


"""
Finds all files modified in that day, and returns a DataFrame with some metrics associated with file size and quantity.
The requests to S3 are done in parallel.
"""


def find_recently_modified_files(
    enriched_content_dictionary: dict, execution_date: datetime
) -> DataFrame:
    inputs = []
    for table in enriched_content_dictionary:
        if table["layer"] not in LAYERS_TO_FETCH_FILES:
            continue
        if table["bucket"] != config_service.get_config("people_bucket"):
            inputs.append((table, execution_date))

    pool = ThreadPool(processes=THREAD_NUMBER)
    outputs = pool.starmap(find_recently_modified_files_by_table, inputs)
    object_tuples = []
    for output in outputs:
        object_tuples += output

    df = create_file_metrics_data_frame(object_tuples)
    return df


"""
Adds file size and quantity data to table DataFrame.
"""


def enrich_table_data_frame_with_file_size_infos(
    content: dict, execution_date: datetime
) -> DataFrame:
    file_info_data_frame = find_recently_modified_files(content, execution_date)
    table_info_data_frame = transform_list_of_dicts_to_dataframe_with_partitions(
        content, execution_date
    )
    return table_info_data_frame.join(
        file_info_data_frame,
        file_info_data_frame.table_name == table_info_data_frame.files_location,
        "left",
    ).select(
        "table",
        "dag",
        "task",
        "layer",
        "files_location",
        "qty_modified_partitions",
        "qty_modified_files",
        "min_file_size_in_bytes",
        "q25_size_in_bytes",
        "q50_size_in_bytes",
        "q75_size_in_bytes",
        "max_file_size_in_bytes",
        "avg_file_size_in_bytes",
        "qty_smaller_than_1mb",
        "qty_bigger_than_1gb",
        "total_modified_files_size_in_bytes",
        "is_delta",
        "year",
        "month",
        "day",
    )


"""
Create a string with dag table schema
"""


def create_dag_dataframe(content, execution_date):
    schema = "dag:string, dag_location:string, cluster_configuration:string"

    df = spark.createDataFrame(
        (Row(**row_content) for row_content in content), schema=schema
    )

    return (
        df.withColumn("year", SF.lit(execution_date.year))
        .withColumn("month", SF.lit(execution_date.month))
        .withColumn("day", SF.lit(execution_date.day))
    )


"""
Given the DagBag content dictionary and execution date, creates a Spark DataFrame with year, month and day.
"""


def transform_list_of_dicts_to_dataframe_with_partitions(content, execution_date):
    r"""
    Tranform a list of dicts in a sparkDataFrame.

    :param content: A list with rows in dict format.
    :type content: List[Dict]
    :param execution_date: The ingestion execution, used to create the ingestion partitions.
    :type execution_date: datetime
    :rtype: sparkDataFrame
    """
    df = spark.createDataFrame(Row(**row_content) for row_content in content)

    return (
        df.withColumn("year", SF.lit(execution_date.year))
        .withColumn("month", SF.lit(execution_date.month))
        .withColumn("day", SF.lit(execution_date.day))
    )


"""
Enriches the content for datalake_dag_inventory_raw.table and transforms it into a DataFrame
"""


def enrich_table(content: dict, execution_date: dict) -> DataFrame:
    enriched_content = enrich_table_dictionary_with_spark_metastore(content)
    return enrich_table_data_frame_with_file_size_infos(
        enriched_content, execution_date
    )


"""
Given the dictionary with the DagBag content and the table name, enriches it appropriately, transforming it into a DataFrame.
"""


def transform_dictionaries_to_dataframe(
    content: dict, execution_date: datetime, table_name: str
) -> DataFrame:
    enrichments = {"table": enrich_table, "dag": create_dag_dataframe}
    return enrichments.get(table_name)(content, execution_date)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("dw_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("execution_date", type=str, help="DAG execution date")
    args = parser.parse_args()

    environment = args.env
    datalake_bucket = args.datalake_bucket
    dw_bucket = args.dw_bucket
    source = args.source
    table_name = args.table_name
    execution_date = datetime.strptime(args.execution_date, "%Y-%m-%d")
    partition_cols = ["year", "month", "day"]

    logger.info(
        f"""
        m=__main__, environment={environment}, datalake_bucket={datalake_bucket}, source={source},
        table_name={table_name}, raw_partition_cols={partition_cols}, execution_date={execution_date}, msg=Starting Spark job...
        """
    )
    spark_client = SparkClient()
    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    spark_metastore_service = MetastoreServiceFactory.create_loader_metastore_service(
        spark_client
    )

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    s3_loader = S3Loader()

    content_dictionary = read_dag_bag_content(table_name, execution_date)

    df = transform_dictionaries_to_dataframe(
        content_dictionary, execution_date, table_name
    )

    s3_loader.load_df(
        df=df,
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
        partitions=partition_cols,
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
        database_name=database_name,
        table_name=table_name,
        df=df,
        partition_cols=partition_cols,
    )
