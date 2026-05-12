"""Transformations for CDF to Kafka with plain JSON format (no wire format)."""

import logging
from typing import List

from pyspark.sql import DataFrame
from pyspark.sql import functions as F

from bietlejuice.services.cdf_services.cdf_to_kafka.transformations.headers import (
    create_kafka_headers,
    get_data_columns_from,
)

logger = logging.getLogger(__name__)


def cdf_to_kafka_format_plain_json(
    cdf_dataframe: DataFrame,
    key_columns: List[str],
    source_table: str,
    entity: str,
) -> DataFrame:
    """Convert CDF DataFrame to Kafka format with plain JSON value.

    Returns DataFrame with columns: headers, key, value (binary JSON without wire format).
    """
    logger.info("Encoding value as plain JSON (no wire format)")

    headers = create_kafka_headers(cdf_dataframe, source_table, entity)
    headers_col = F.array(*headers).alias("headers")

    keys = [F.col(col) for col in key_columns]
    keys_struct = F.struct(*keys)
    keys_col = F.to_json(keys_struct).alias("key")

    data_columns = get_data_columns_from(cdf_dataframe)
    data_columns = [F.col(col) for col in data_columns]
    data_struct = F.struct(*data_columns)
    values_col = F.to_json(data_struct).cast("binary").alias("value")

    # Drop _change_type before writing to Kafka (only needed for metrics)
    return cdf_dataframe.select(
        headers_col, keys_col, values_col, F.col("_change_type")
    )
