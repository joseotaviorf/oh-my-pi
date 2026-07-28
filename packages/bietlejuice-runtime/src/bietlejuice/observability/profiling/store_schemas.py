"""Explicit Spark schemas for the observability store.

The store tables are append-only and their columns are documented in
``dags/governance/data_observability/metadata/raw/*.yml``. Schemas are declared
explicitly (rather than inferred) so a run whose collected records have all-null
or empty-collection fields still writes with the correct, stable types.

Records produced by the profiling pipeline are plain dicts (nested structs are
nested dicts, maps are dicts); :class:`ObservabilityStoreWriter` maps them onto
these schemas by field name, so field order here is the single source of truth.
"""

from __future__ import annotations

from pyspark.sql.types import (
    ArrayType,
    IntegerType,
    LongType,
    MapType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)

_NAME_TYPE_STRUCT = StructType(
    [
        StructField("name", StringType(), True),
        StructField("type", StringType(), True),
    ]
)

_NAME_VALUE_STRUCT = StructType(
    [
        StructField("name", StringType(), True),
        StructField("value", StringType(), True),
    ]
)

TABLE_METRICS_SCHEMA = StructType(
    [
        StructField("database", StringType(), True),
        StructField("table", StringType(), True),
        StructField("layer", StringType(), True),
        StructField("environment", StringType(), True),
        StructField("run_logical_date", StringType(), True),
        StructField("profiled_delta_version", LongType(), True),
        StructField("profiled_at", TimestampType(), True),
        StructField("collection_method", StringType(), True),
        StructField("metric_schema_version", IntegerType(), True),
        StructField("row_count", LongType(), True),
        StructField("num_files", LongType(), True),
        StructField("size_bytes", LongType(), True),
        StructField("created_at", TimestampType(), True),
        StructField("last_modified", TimestampType(), True),
        StructField("latest_partition_value", StringType(), True),
        StructField("num_columns", IntegerType(), True),
        StructField("schema_hash", StringType(), True),
        StructField("columns", ArrayType(_NAME_TYPE_STRUCT), True),
        StructField("partition_columns", ArrayType(StringType()), True),
        StructField("clustering_columns", ArrayType(StringType()), True),
        StructField("table_properties", MapType(StringType(), StringType()), True),
        StructField("table_features", ArrayType(StringType()), True),
        StructField("year", IntegerType(), True),
        StructField("month", IntegerType(), True),
        StructField("day", IntegerType(), True),
    ]
)

PARTITION_METRICS_SCHEMA = StructType(
    [
        StructField("database", StringType(), True),
        StructField("table", StringType(), True),
        StructField("layer", StringType(), True),
        StructField("environment", StringType(), True),
        StructField("run_logical_date", StringType(), True),
        StructField("profiled_delta_version", LongType(), True),
        StructField("profiled_at", TimestampType(), True),
        StructField("collection_method", StringType(), True),
        StructField("metric_schema_version", IntegerType(), True),
        StructField("partition_key", ArrayType(_NAME_VALUE_STRUCT), True),
        StructField("row_count", LongType(), True),
        StructField("rows_written", LongType(), True),
        StructField("num_files", LongType(), True),
        StructField("size_bytes", LongType(), True),
        StructField("min_ts", TimestampType(), True),
        StructField("max_ts", TimestampType(), True),
        StructField("year", IntegerType(), True),
        StructField("month", IntegerType(), True),
        StructField("day", IntegerType(), True),
    ]
)

PARTITION_COLUMNS = ["year", "month", "day"]
