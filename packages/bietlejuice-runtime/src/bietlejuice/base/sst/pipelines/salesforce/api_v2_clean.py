"""Salesforce API_v2 clean-layer pipeline (SCD Type 2).

Reads a daily API_v2 raw snapshot (``datalake_salesforce_raw.<object>_v2``) and
maintains an SCD Type 2 history table in the clean layer
(``datalake_salesforce_clean.<object>_v2``): new records are inserted as the current
version, changed records get a new current version while the previous one is expired,
and exactly one ``_is_current=true`` row is kept per ``id_record``. Volume metrics are
emitted and the table is synced to Trino + the secondary catalog (Glue/Unity).

Entry point name: ``salesforce/api_v2_clean``. The job is object-agnostic — the object
is selected entirely via ``--target_table`` / ``--target_schema`` / ``--source_schema``.
"""

import pyspark.sql.functions as F
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.sst.core.observability.metrics import save_volume_metric
from bietlejuice.base.sst.core.observability.sensors import partition_has_data
from bietlejuice.base.sst.core.quality.checks import basic_quality_checks
from bietlejuice.base.sst.core.utils.common import (
    _table_exists,
    default_args,
    retrieve_spark_session,
    validate_and_upsert,
    validate_and_write,
)
from bietlejuice.base.sst.core.utils.time import standard_now
from bietlejuice.base.sst.domains.salesforce.clean.api_versioning import (
    build_api_versioned_df,
    conform_api_clean,
)

logger = QuintoAndarLogger("sst.pipelines.salesforce.api_v2_clean")

# Business key for versioning. ``Id`` is renamed to ``id_record`` in api_v2 raw
# (see pipelines/salesforce/api_v2.py) and ``normalize_column_name`` leaves it as-is.
CONTEXT_COL = "id_record"

# Salesforce ``SystemModstamp`` (normalized) — the field the raw incremental is keyed
# on and the most monotonic "last system modification" stamp; used to order versions.
EVENT_TS_COL = "system_modstamp"

# Match key for the SCD Type 2 Delta MERGE: one row per record version.
MERGE_MATCH_FIELDS = ["id_record", "_effective_timestamp"]


@default_args(
    optional_args=[
        dict(
            name="dag_name",
            flags=["--dag_name", "--dag-name"],
            type=str,
            required=False,
            default="",
            help="DAG name (optional).",
        ),
        dict(
            name="partition_date",
            flags=["--partition_date", "--partition-date"],
            type=str,
            required=True,
            help="Partition date (YYYY-MM-DD).",
        ),
        dict(
            name="partition_hour",
            flags=["--partition_hour", "--partition-hour"],
            type=str,
            required=False,
            default=None,
            help="Partition hour (HH). Optional; when omitted the job runs at "
            "daily granularity.",
        ),
        dict(
            name="bucket",
            flags=["--bucket"],
            type=str,
            required=True,
            help="S3 Bucket Name.",
        ),
        dict(
            name="source_schema",
            flags=["--source_schema", "--source-schema"],
            type=str,
            required=True,
            help="Source schema (datalake_salesforce_raw).",
        ),
        dict(
            name="sync_hive",
            flags=["--sync_hive", "--sync-hive"],
            type=lambda x: x.lower() == "true",
            required=False,
            default=False,
            help="When true, registers/updates the table in Trino's Delta catalog "
            "after writing. Requires table_location to be set.",
        ),
    ]
)
@logger(exclude_return=True)
def salesforce_api_clean_pipeline(cfg):
    job_name = f"{cfg.dag_name}.{cfg.job_name}"
    logger.info(f"m=salesforce_api_clean_pipeline, msg=Starting for {job_name=}")
    logger.info(f"m=salesforce_api_clean_pipeline, msg=Config: {cfg=}")
    spark = retrieve_spark_session(job_name=job_name)

    source_table = f"{cfg.source_schema}.{cfg.target_table}"
    target_table = f"{cfg.target_schema}.{cfg.target_table}"

    if not partition_has_data(
        spark, source_table, cfg.partition_date, cfg.partition_hour
    ):
        logger.info(
            f"m=salesforce_api_clean_pipeline, msg=No raw data for {source_table} "
            f"{cfg.partition_date} hour={cfg.partition_hour}; exiting"
        )
        return

    raw_df = spark.read.table(source_table).where(
        F.col("partition_date") == cfg.partition_date
    )
    # "00" is a legitimate hour — compare against None, never truthiness.
    if cfg.partition_hour is not None:
        raw_df = raw_df.where(F.col("partition_hour") == cfg.partition_hour)

    conformed_df = conform_api_clean(raw_df, CONTEXT_COL)
    versioned_df = build_api_versioned_df(
        spark, conformed_df, target_table, CONTEXT_COL, EVENT_TS_COL
    )

    # Fresh clean processing timestamp (the ticket's required ``ts_load``). partition_date
    # is preserved from the source rows so each version keeps the ingest day it came from.
    out_df = versioned_df.withColumn("ts_load", F.lit(standard_now()))

    basic_quality_checks(
        out_df,
        required_cols=[CONTEXT_COL, EVENT_TS_COL, "_is_current"],
        unique_grain=MERGE_MATCH_FIELDS,
        fail=True,
    )
    logger.info("m=salesforce_api_clean_pipeline, msg=Quality checks passed")

    table_location = f"s3a://{cfg.bucket}/clean/salesforce/{cfg.target_table}"
    if _table_exists(spark, target_table):
        # Incremental SCD2 merge: close reopened prior versions and insert new ones.
        logger.info(
            "m=salesforce_api_clean_pipeline, msg=Upserting into existing target"
        )
        validate_and_upsert(
            spark,
            target_table=target_table,
            source_df=out_df,
            match_fields=MERGE_MATCH_FIELDS,
        )
    else:
        # Bootstrap: create the table (partitioned by _is_current) and sync catalogs.
        logger.info("m=salesforce_api_clean_pipeline, msg=Bootstrapping target table")
        validate_and_write(
            spark,
            out_df,
            target_table=target_table,
            partition_cols=["_is_current"],
            overwrite_schema=True,
            table_location=table_location,
            sync_hive=cfg.sync_hive,
            sync_secondary_catalog=True,
        )

    logger.info("m=salesforce_api_clean_pipeline, msg=Saving volume metric")
    # Incremental runs align to the target's schema (safe_union_with_target_schema),
    # so partition_hour only survives to out_df once the clean table carries it —
    # hence the column-presence guard on top of the hour check.
    metric_grain = ["partition_date"]
    if cfg.partition_hour is not None and "partition_hour" in out_df.columns:
        metric_grain.append("partition_hour")
    save_volume_metric(
        spark=spark,
        df=out_df,
        grain=metric_grain,
        metric_name="api_clean_volume",
        table_name=target_table,
        env=cfg.env,
        layer="clean",
        partition_cols=["partition_date"],
        table_location=f"s3a://{cfg.bucket}/sst_metrics/api_clean_volume",
    )

    logger.info("m=salesforce_api_clean_pipeline, msg=Pipeline completed")


if __name__ == "__main__":
    salesforce_api_clean_pipeline()
