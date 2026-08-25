"""Shared CDC event helpers used across SST domain pipelines."""

from pyspark.sql import functions as F


def retrieve_missing_events(
    spark,
    target_table,
    partition_date,
    partition_hour,
    raw_schema,
    clean_schema,
):
    """Return ``id_record`` values present in raw but missing from clean.

    The comparison is scoped to a single ``partition_date`` / ``partition_hour``.
    """
    raw = (
        spark.read.table(f"{raw_schema}.{target_table}")
        .where(F.col("partition_date") == partition_date)
        .where(F.col("partition_hour") == partition_hour)
    )
    clean = (
        spark.read.table(f"{clean_schema}.{target_table}")
        .where(F.col("partition_date") == partition_date)
        .where(F.col("partition_hour") == partition_hour)
    )
    missing_ids = (
        raw.join(clean, on="id_record", how="left_anti").select("id_record").distinct()
    )
    return [row["id_record"] for row in missing_ids.collect()]
