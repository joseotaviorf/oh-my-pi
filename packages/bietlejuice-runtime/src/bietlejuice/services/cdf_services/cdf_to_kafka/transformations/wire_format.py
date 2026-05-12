"""Transformations for CDF to Kafka with Confluent Schema Registry wire format."""

import logging
import struct
from typing import List

import pandas as pd
from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from pyspark.sql.functions import pandas_udf
from pyspark.sql.types import BinaryType

from bietlejuice.services.cdf_services.cdf_to_kafka.transformations.headers import (
    create_kafka_headers,
    get_data_columns_from,
)

logger = logging.getLogger(__name__)

CONFLUENT_MAGIC_BYTE = b"\x00"


def _create_confluent_encoder_udf(schema_id: int):
    """Create a Pandas UDF for encoding JSON with Confluent wire format.

    Pre-computes the wire format prefix (magic byte + schema_id) once
    for better performance, since all rows share the same schema.

    Wire format structure:
    - Byte 0: Magic byte (0x00)
    - Bytes 1-4: Schema ID (4 bytes, big-endian)
    - Bytes 5+: JSON payload
    """
    schema_id_bytes = struct.pack(">I", schema_id)
    wire_format_prefix = CONFLUENT_MAGIC_BYTE + schema_id_bytes

    @pandas_udf(BinaryType())
    def encode_udf(json_series: pd.Series) -> pd.Series:
        return json_series.apply(
            lambda json_str: wire_format_prefix + json_str.encode("utf-8")
        )

    return encode_udf


def cdf_to_kafka_format_with_schema_registry(
    cdf_dataframe: DataFrame,
    key_columns: List[str],
    source_table: str,
    schema_id: int,
    entity: str,
) -> DataFrame:
    """Convert CDF DataFrame to Kafka format with Confluent wire format encoding.

    The value column is encoded using Confluent wire format:
    - Byte 0: Magic byte (0x00)
    - Bytes 1-4: Schema ID (4 bytes, big-endian)
    - Bytes 5+: JSON payload

    This format is required for Confluent Schema Registry compatibility, allowing
    consumers to deserialize messages using the schema_id embedded in the payload.

    Args:
        cdf_dataframe: DataFrame with CDF columns
        key_columns: List of column names to use as Kafka key
        source_table: Source table name
        schema_id: Schema ID from Schema Registry to encode in value payload
        entity: Entity name

    Returns:
        DataFrame with 3 columns: headers, key, value (binary with Confluent wire format)
    """
    logger.info(f"Encoding value with Confluent wire format (schema_id={schema_id})")

    data_columns = get_data_columns_from(cdf_dataframe)

    headers = create_kafka_headers(cdf_dataframe, source_table, entity, schema_id)
    headers_col = F.array(*headers).alias("headers")

    keys = [F.col(col) for col in key_columns]
    keys_struct = F.struct(*keys)
    keys_col = F.to_json(keys_struct).alias("key")

    values = [F.col(col) for col in data_columns]
    values_struct = F.struct(*values)
    values_col = F.to_json(values_struct)
    encoder_udf = _create_confluent_encoder_udf(schema_id)
    values_col_encoded = encoder_udf(values_col).alias("value")

    # Drop _change_type before writing to Kafka (only needed for metrics)
    return cdf_dataframe.select(
        headers_col, keys_col, values_col_encoded, F.col("_change_type")
    )
