"""
Storage format configurations for AWS Glue Data Catalog table registration.

Maps table formats (DELTA, PARQUET, JSON) to their corresponding
InputFormat, OutputFormat, SerDe, and classification values expected by the
Glue Data Catalog API.

Lives under ``metastore_services`` (not ``base.spark``) so importing
``GlueMetastoreService`` does not execute ``bietlejuice.base.spark``'s
package ``__init__``, which would create a ``SparkContext`` on import and
break executor-side deserialization (SPARK-5063).

Ported from the UC-Glue bi-directional sync script.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict

_PARQUET_INPUT = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
_PARQUET_OUTPUT = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
_PARQUET_SERDE = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
_JSON_INPUT = "org.apache.hadoop.mapred.TextInputFormat"
_JSON_OUTPUT = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"
_JSON_SERDE = "org.openx.data.jsonserde.JsonSerDe"
# Delta: Hive-compatible stub (SequenceFile + LazySimpleSerDe) + Spark
# table properties — matches UC→Glue sync and Spark/EMR Delta recognition.
_DELTA_INPUT = "org.apache.hadoop.mapred.SequenceFileInputFormat"
_DELTA_OUTPUT = "org.apache.hadoop.hive.ql.io.HiveSequenceFileOutputFormat"
_DELTA_SERDE = "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe"


@dataclass(frozen=True)
class StorageFormatConfig:
    input_format: str
    output_format: str
    serialization_library: str
    classification: str
    serde_params: Dict[str, str] = field(default_factory=dict)
    table_params: Dict[str, str] = field(default_factory=dict)


GLUE_STORAGE_FORMATS: Dict[str, StorageFormatConfig] = {
    "DELTA": StorageFormatConfig(
        input_format=_DELTA_INPUT,
        output_format=_DELTA_OUTPUT,
        serialization_library=_DELTA_SERDE,
        classification="delta",
        serde_params={"serialization.format": "1"},
        table_params={
            "spark.sql.sources.provider": "delta",
            "spark.sql.sources.schema": '{"type":"struct","fields":[]}',
            "spark.sql.partitionProvider": "catalog",
            "EXTERNAL": "TRUE",
        },
    ),
    "PARQUET": StorageFormatConfig(
        input_format=_PARQUET_INPUT,
        output_format=_PARQUET_OUTPUT,
        serialization_library=_PARQUET_SERDE,
        classification="parquet",
        serde_params={"serialization.format": "1"},
    ),
    "JSON": StorageFormatConfig(
        input_format=_JSON_INPUT,
        output_format=_JSON_OUTPUT,
        serialization_library=_JSON_SERDE,
        classification="json",
    ),
}


def get_glue_format_config(table_format: str) -> StorageFormatConfig:
    """Return the Glue storage format config for a given table format.

    :param table_format: One of DELTA, PARQUET, JSON (case-insensitive).
    :raises ValueError: If the format is not supported.
    """
    key = table_format.upper()
    if key not in GLUE_STORAGE_FORMATS:
        raise ValueError(
            f"Unsupported table format '{table_format}'. "
            f"Supported: {list(GLUE_STORAGE_FORMATS.keys())}"
        )
    return GLUE_STORAGE_FORMATS[key]
