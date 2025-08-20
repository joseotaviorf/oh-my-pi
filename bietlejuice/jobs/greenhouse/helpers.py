import re
import pandas as pd
from pyspark.sql import DataFrame
from pyspark.sql.types import StructType, StructField, ArrayType
from pyspark.sql.functions import (
    to_json,
    from_json,
    struct,
    col,
    now,
    to_timestamp,
    year,
    month,
    dayofmonth,
)
from quintoandar_logger import QuintoAndarLogger

LOGGER = QuintoAndarLogger(__name__)


def sanitize_name(name: str) -> str:
    """Replaces special characters in a field name with underscores."""
    cleaned_name = re.sub(r"[^a-zA-Z0-9_]", "_", name)
    if cleaned_name and cleaned_name[0].isdigit():
        cleaned_name = "_" + cleaned_name
    return cleaned_name


def sanitize_schema(schema: StructType) -> StructType:
    """
    Recursively traverses a Spark schema and applies the sanitization
    function to all field names, including those in nested structs and arrays.
    """
    new_fields = []
    for field in schema.fields:
        new_name = sanitize_name(field.name)
        new_data_type = field.dataType

        if isinstance(field.dataType, StructType):
            new_data_type = sanitize_schema(field.dataType)
        elif isinstance(field.dataType, ArrayType) and isinstance(
            field.dataType.elementType, StructType
        ):
            new_data_type = ArrayType(
                sanitize_schema(field.dataType.elementType), field.dataType.containsNull
            )

        new_fields.append(StructField(new_name, new_data_type, field.nullable))

    return StructType(new_fields)


def json_to_dataframe(spark, api_data_list: list):
    """
    Converts a list of dictionaries into a Spark DataFrame using a Pandas
    DataFrame as an intermediate bridge to robustly handle inconsistent schemas.
    """
    if not api_data_list:
        return spark.createDataFrame([], schema=StructType([]))

    pandas_df = pd.DataFrame(api_data_list)
    inferred_df = spark.createDataFrame(pandas_df)
    clean_schema = sanitize_schema(inferred_df.schema)
    df_clean = (
        inferred_df.select(to_json(struct("*")).alias("json_string"))
        .select(from_json(col("json_string"), clean_schema).alias("data"))
        .select("data.*")
    )

    return df_clean


def insert_partitions(
    df: DataFrame, date_column_to_partition: str = None, datetime_format: str = None
) -> DataFrame:
    """
    Adds year, month, and day partition columns to a DataFrame.

    Partitions are derived from a specified date/timestamp column or, as a
    fallback, from the current timestamp when the function is executed.
    """
    if df is None:
        LOGGER.error("insert_partitions received a None DataFrame. Returning None.")
        return None

    df = df.withColumn("ts_load", now())

    if date_column_to_partition in df.columns:
        LOGGER.info(f"Using column '{date_column_to_partition}' for partitioning.")
        source_for_timestamp = (
            to_timestamp(col(date_column_to_partition), datetime_format)
            if datetime_format
            else to_timestamp(col(date_column_to_partition))
        )
    else:
        LOGGER.error(f"Partition column '{date_column_to_partition}' not found. ")

    df = df.withColumn("year", year(source_for_timestamp))
    df = df.withColumn("month", month(source_for_timestamp))
    df = df.withColumn("day", dayofmonth(source_for_timestamp))

    if date_column_to_partition and date_column_to_partition in df.columns:
        null_partition_count = df.where(col("year").isNull()).count()
        if null_partition_count > 0:
            total_count = df.count()
            LOGGER.warning(
                f"{null_partition_count} out of {total_count} rows have null partition values "
                f"due to failed date conversion on column '{date_column_to_partition}'."
            )
            if null_partition_count == total_count:
                raise ValueError(
                    f"All date conversions failed for partition column '{date_column_to_partition}'. "
                    "Halting job to prevent writing to a null partition."
                )

    return df
