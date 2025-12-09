import logging

from pyspark.sql import DataFrame
from typing import Optional

from .cdf_plain_json_transformations import (
    cdf_to_kafka_format_plain_json,
)
from .cdf_wire_format_transformations import (
    cdf_to_kafka_format_with_schema_registry,
)

logger = logging.getLogger(__name__)


def filter_cdf_events(df: DataFrame) -> DataFrame:
    """Filter CDF events to include only inserts and update post-images."""
    logger.info("Filtering CDF events: insert and update_postimage only")
    return df.filter(df._change_type.isin(["insert", "update_postimage"]))


def drop_partition_columns(df: DataFrame) -> DataFrame:
    """Drop common partition columns from the DataFrame."""
    columns_to_drop = ["year", "month", "day"]
    existing_columns = df.columns
    columns_to_remove = [col for col in columns_to_drop if col in existing_columns]

    if columns_to_remove:
        logger.info(f"Dropping partition columns: {columns_to_remove}")
        return df.drop(*columns_to_remove)

    return df


def cdf_to_kafka_format(
    cdf_dataframe: DataFrame,
    key_columns: list[str],
    source_table: str,
    schema_id: Optional[int],
    entity: str = None,
    use_schema_registry: bool = True,
) -> DataFrame:
    """Convert CDF DataFrame to Kafka format with headers, key, and value columns.

    This function transforms the DataFrame to match the required format for Spark's
    Kafka connector, which expects specific column types:
    - headers: array<struct<key: string, value: binary>> - Kafka message headers
    - key: string or binary - Kafka message key (JSON string in this implementation)
    - value: string or binary - Kafka message payload (JSON or wire format encoded)

    When use_schema_registry is True, delegates to wire format encoding.
    When use_schema_registry is False, uses plain JSON encoding.

    Args:
        cdf_dataframe: DataFrame with CDF columns
        key_columns: List of column names to use as Kafka key
        source_table: Source table name
        schema_id: Schema ID from Schema Registry (required when use_schema_registry=True)
        entity: Entity name
        use_schema_registry: Whether to use Confluent Schema Registry with wire format

    Returns:
        DataFrame with 3 columns: headers, key, value
    """

    if entity is None:
        raise ValueError("Parameter 'entity' is required")

    if use_schema_registry:
        if schema_id is None:
            raise ValueError("schema_id is required when use_schema_registry=True")
        return cdf_to_kafka_format_with_schema_registry(
            cdf_dataframe, key_columns, source_table, schema_id, entity
        )
    else:
        return cdf_to_kafka_format_plain_json(
            cdf_dataframe, key_columns, source_table, entity
        )
