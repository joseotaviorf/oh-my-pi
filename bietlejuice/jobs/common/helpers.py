import re
import json
import logging
from pyspark.sql import DataFrame, SparkSession
from pyspark.sql.types import StructType
from pyspark.sql.functions import col, now, to_timestamp, year, month, dayofmonth

LOGGER = logging.getLogger(__name__)


def clean_keys_recursive(obj):
    """
    Recursively walks a data structure and replaces hyphens and other
    special characters with underscores in dictionary keys.
    """
    if isinstance(obj, dict):
        cleaned_dict = {}
        for k, v in obj.items():
            cleaned_key = re.sub(r"[^a-zA-Z0-9_]", "_", k)
            if cleaned_key and cleaned_key[0].isdigit():
                cleaned_key = "_" + cleaned_key
            cleaned_dict[cleaned_key] = clean_keys_recursive(v)
        return cleaned_dict
    elif isinstance(obj, list):
        return [clean_keys_recursive(elem) for elem in obj]
    else:
        return obj


def json_to_dataframe(
    spark: SparkSession, api_data_list: list, raw_column_name: str = None
) -> DataFrame:
    """
    Converts a list of dictionaries into a Spark DataFrame dynamically.

    This approach first cleans the keys in the raw data, then uses Spark's
    native inference engine on an RDD of JSON strings, making it robust against
    inconsistent schemas and invalid characters in field names.

    If ``raw_column_name`` is provided, the original JSON payload of each
    record (before key normalization) is stored as a string in that column.
    """
    if not api_data_list:
        return spark.createDataFrame([], schema=StructType([]))

    cleaned_api_data_list = []
    if raw_column_name:
        for record in api_data_list:
            cleaned_record = clean_keys_recursive(record)
            cleaned_record[raw_column_name] = json.dumps(record)
            cleaned_api_data_list.append(cleaned_record)
    else:
        cleaned_api_data_list = [
            clean_keys_recursive(record) for record in api_data_list
        ]

    rdd_json_strings = spark.sparkContext.parallelize(
        [json.dumps(record) for record in cleaned_api_data_list]
    )

    df = spark.read.json(rdd_json_strings)

    return df


def insert_partitions(
    df: DataFrame, date_column_to_partition: str = None, datetime_format: str = None
) -> DataFrame:
    """
    Adds partition columns (year, month, day) to a DataFrame.

    Partitions are derived from a specified date/timestamp column or, as a
    fallback, from the current timestamp when the function is executed.
    """
    if df is None:
        LOGGER.error("insert_partitions received a null DataFrame. Returning None.")
        return None

    df = df.withColumn("ts_load", now())
    source_for_timestamp = col("ts_load")

    if date_column_to_partition and date_column_to_partition in df.columns:
        LOGGER.info(f"Using column '{date_column_to_partition}' for partitioning.")
        source_for_timestamp = (
            to_timestamp(col(date_column_to_partition), datetime_format)
            if datetime_format
            else to_timestamp(col(date_column_to_partition))
        )
    else:
        LOGGER.warning(
            f"Partition column '{date_column_to_partition}' not found. "
            f"Using 'ts_load' as a fallback."
        )

    df = df.withColumn("year", year(source_for_timestamp))
    df = df.withColumn("month", month(source_for_timestamp))
    df = df.withColumn("day", dayofmonth(source_for_timestamp))

    if date_column_to_partition and date_column_to_partition in df.columns:
        null_partition_count = df.where(col("year").isNull()).count()
        if null_partition_count > 0:
            total_count = df.count()
            LOGGER.warning(
                f"{null_partition_count} out of {total_count} rows have null partitions "
                f"due to a failed conversion on column '{date_column_to_partition}'."
            )
            if null_partition_count == total_count:
                raise ValueError(
                    f"All date conversions failed for column '{date_column_to_partition}'. "
                    "Job halted to prevent writing to a null partition."
                )

    return df
