"""Shared constants and functions for CDF Kafka transformations."""

from typing import List, Optional

from pyspark.sql import Column, DataFrame
from pyspark.sql import functions as F

CDF_METADATA_COLUMNS = [
    "_change_type",
    "_commit_version",
    "_commit_timestamp",
]


def _create_cdf_column_headers(cdf_dataframe: DataFrame) -> List[Column]:
    """Create headers from CDF metadata columns present in the DataFrame."""
    headers = []
    for col in cdf_dataframe.columns:
        if col in CDF_METADATA_COLUMNS:
            headers.append(
                F.struct(
                    F.lit(col).alias("key"),
                    F.col(col).cast("string").cast("binary").alias("value"),
                )
            )
    return headers


def _create_static_headers(
    source_table: str,
    entity: str,
    schema_id: Optional[int] = None,
) -> List[Column]:
    """Create static headers with literal values."""
    headers = []

    feature_set_name = source_table.split(".")[-1].replace("__latest", "")
    static_headers = [
        ("source_table", source_table),
        ("feature_set_name", feature_set_name),
        ("entity", entity),
    ]
    if schema_id is not None:
        static_headers.append(("schema_id", str(schema_id)))

    for key, value in static_headers:
        headers.append(
            F.struct(
                F.lit(key).alias("key"),
                F.lit(value).cast("binary").alias("value"),
            )
        )

    return headers


def create_kafka_headers(
    cdf_dataframe: DataFrame,
    source_table: str,
    entity: str,
    schema_id: Optional[int] = None,
) -> List[Column]:
    """Create Kafka headers for CDF messages."""
    cdf_headers = _create_cdf_column_headers(cdf_dataframe)
    static_headers = _create_static_headers(source_table, entity, schema_id)
    return cdf_headers + static_headers


def get_data_columns_from(dataframe: DataFrame) -> List[str]:
    """Get data columns from DataFrame, excluding CDF metadata columns."""
    return [col for col in dataframe.columns if col not in CDF_METADATA_COLUMNS]
