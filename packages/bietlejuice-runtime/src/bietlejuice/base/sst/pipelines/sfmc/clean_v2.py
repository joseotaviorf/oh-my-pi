"""SFMC clean layer for the file-based (SFTP) ingestion.

Copies one ``partition_date`` of a raw SFMC extract table (built by
``pipelines/sfmc/raw_v2``) into the clean layer, so each day of the clean table
is a snapshot of the file delivered that day. There is no history: the clean
table carries the same grain as raw, one partition per delivery.

The clean layer is where the row contract is enforced. Every row must carry an
``event_id`` and a ``source_data_extension``, and the pair must be unique within
the day — three checks in total. A row that fails any of them does not reach the
clean table; it goes to a dead-letter table in the DLQ schema, stamped with when
it was rejected and with one flag per check it failed. Per-check failure counts
are recorded in ``datalake_sst_metrics.pipeline_quality_checks``.

Entry point name: ``sfmc/clean_v2``. One run handles one table, selected via
``--target_table`` / ``--target_schema`` / ``--source_schema``, so the job is
extract-agnostic. The team is identified by the schemas, one set per team
(``datalake_sfmc_{team}_raw`` -> ``datalake_sfmc_{team}_clean`` +
``datalake_sfmc_{team}_dlq``), which is also what scopes the grain-uniqueness
check to a single team: two teams reusing an ``event_id`` never meet.
"""

import pyspark.sql.functions as F
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.sst.core.observability.metrics import (
    save_quality_check_metric,
    save_volume_metric,
)
from bietlejuice.base.sst.core.observability.sensors import partition_has_data
from bietlejuice.base.sst.core.utils.common import (
    _table_exists,
    build_partition_filter,
    default_args,
    normalize_df_columns,
    retrieve_spark_session,
    validate_and_write,
    validate_partition_readability,
)
from bietlejuice.base.sst.core.utils.time import standard_now
from bietlejuice.base.sst.domains.sfmc.clean.quality import (
    CHECK_COLS,
    conform_required_columns,
    flag_quality_checks,
    split_checked_rows,
)

logger = QuintoAndarLogger("sst.pipelines.sfmc.clean_v2")

VOLUME_METRIC_NAME = "sfmc_clean_volume"
QUALITY_METRIC_NAME = "sfmc_clean_quality_checks"


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
            help="Source schema, one per team (datalake_sfmc_<team_name>_raw).",
        ),
        dict(
            name="dlq_schema",
            flags=["--dlq_schema", "--dlq-schema"],
            type=str,
            required=True,
            help="Schema holding the dead-letter tables, one per team "
            "(datalake_sfmc_<team_name>_dlq).",
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
def sfmc_clean_v2_pipeline(cfg):
    job_name = f"{cfg.dag_name}.{cfg.job_name}"
    logger.info(f"m=sfmc_clean_v2_pipeline, msg=Starting for {job_name=}")
    logger.info(f"m=sfmc_clean_v2_pipeline, msg=Config: {cfg=}")

    spark = retrieve_spark_session(job_name=job_name)

    source_table = f"{cfg.source_schema}.{cfg.target_table}"
    target_table = f"{cfg.target_schema}.{cfg.target_table}"
    dlq_table = f"{cfg.dlq_schema}.{cfg.target_table}"

    if not partition_has_data(spark, source_table, cfg.partition_date):
        logger.info(
            f"m=sfmc_clean_v2_pipeline, msg=No raw data for {source_table} "
            f"{cfg.partition_date}; exiting"
        )
        return

    raw_df = spark.read.table(source_table).where(
        F.col("partition_date") == F.lit(cfg.partition_date)
    )

    # Raw lands the delivered headers verbatim, so snake_casing them is this
    # layer's job: it is what turns a delivered EventID into id_event, which
    # conform_required_columns then renames to the contract's event_id.
    conformed_df = conform_required_columns(normalize_df_columns(raw_df))
    # Read three times below (metric, clean write, DLQ write), and the checks
    # include a window aggregation, so materialize it once.
    flagged_df = flag_quality_checks(conformed_df).cache()

    try:
        accepted_df, rejected_df = split_checked_rows(
            flagged_df, dlq_timestamp=standard_now()
        )

        _write_clean_table(
            spark=spark, cfg=cfg, target_table=target_table, accepted_df=accepted_df
        )
        _write_dlq_table(
            spark=spark, cfg=cfg, dlq_table=dlq_table, rejected_df=rejected_df
        )

        logger.info("m=sfmc_clean_v2_pipeline, msg=Saving quality check metric")
        save_quality_check_metric(
            spark=spark,
            flagged_df=flagged_df,
            check_cols=CHECK_COLS,
            bucket=cfg.bucket,
            target_table=target_table,
            partition_date=cfg.partition_date,
            env=cfg.env,
            layer="clean",
            metric_name=QUALITY_METRIC_NAME,
        )
    finally:
        flagged_df.unpersist()

    logger.info("m=sfmc_clean_v2_pipeline, msg=Pipeline completed")


def _write_clean_table(spark, cfg, target_table, accepted_df):
    """Publish the rows that passed every check, then verify they read back.

    A day with nothing accepted (every row failed the contract) still
    overwrites the partition when the clean table already exists — otherwise
    a rerun after SFMC re-delivers a corrected, now fully-rejected file would
    leave the previous run's accepted rows behind. The table is only created
    once something is actually accepted, so a first run that is 100% DLQ
    never materializes an empty clean table. The post-write readback check is
    skipped in that same all-rejected case: reading back a partition that was
    written empty on purpose would just confirm the expected empty result,
    not signal a real write failure.
    """
    out_df = accepted_df.withColumn("ts_load", F.lit(standard_now())).withColumn(
        "partition_date", F.lit(cfg.partition_date)
    )

    accepted_count = out_df.count()
    table_exists = _table_exists(spark, target_table)

    if accepted_count == 0 and not table_exists:
        logger.warning(
            "m=_write_clean_table, msg=No accepted rows and no clean table "
            f"yet, nothing to write, target_table={target_table}"
        )
        return

    log_level = logger.warning if accepted_count == 0 else logger.info
    log_level(
        f"m=_write_clean_table, msg=Writing {accepted_count} accepted rows, "
        f"target_table={target_table}, partition_date={cfg.partition_date}"
    )

    # Day overwrite, so a rerun replaces the snapshot instead of duplicating it
    # (raw itself is replaceable, e.g. when SFMC re-delivers a corrected file).
    validate_and_write(
        spark=spark,
        df=out_df,
        target_table=target_table,
        partition_filter=build_partition_filter({"partition_date": cfg.partition_date}),
        partition_cols=["partition_date"],
        overwrite_schema=True,
        table_location=f"s3a://{cfg.bucket}/clean/{cfg.target_schema}/{cfg.target_table}",
        sync_hive=cfg.sync_hive,
        sync_secondary_catalog=True,
    )

    if accepted_count > 0:
        try:
            validate_partition_readability(
                spark=spark,
                target_table=target_table,
                partition_date=cfg.partition_date,
            )
        except Exception as err:
            raise RuntimeError(
                "Clean table write succeeded but post-write readback failed for "
                f"table={target_table}, partition_date={cfg.partition_date}. "
            ) from err

    logger.info("m=_write_clean_table, msg=Saving volume metric")
    save_volume_metric(
        spark=spark,
        df=out_df,
        grain=["partition_date"],
        metric_name=VOLUME_METRIC_NAME,
        table_name=target_table,
        env=cfg.env,
        layer="clean",
        partition_cols=["partition_date"],
        table_location=f"s3a://{cfg.bucket}/sst_metrics/{VOLUME_METRIC_NAME}",
        fallback_grain_values={"partition_date": cfg.partition_date},
    )


def _write_dlq_table(spark, cfg, dlq_table, rejected_df):
    """Write the rejected rows for the day, if there is a DLQ to maintain.

    A day with nothing rejected still overwrites the partition when the DLQ
    table already exists, which clears rejects left by an earlier run of the
    same day — otherwise a rerun after SFMC re-delivered a corrected file would
    leave the old rejects behind, reading as if they were never fixed. The
    table is only created once something is actually rejected, so a table that
    never fails a check never materializes an empty DLQ.
    """
    rejected_count = rejected_df.count()
    dlq_exists = _table_exists(spark, dlq_table)

    if rejected_count == 0 and not dlq_exists:
        logger.info(
            "m=_write_dlq_table, msg=No rejected rows and no DLQ table yet, "
            f"nothing to create, dlq_table={dlq_table}"
        )
        return

    log_level = logger.warning if rejected_count else logger.info
    log_level(
        f"m=_write_dlq_table, msg=Writing {rejected_count} rejected rows, "
        f"dlq_table={dlq_table}, partition_date={cfg.partition_date}"
    )

    out_df = rejected_df.withColumn("partition_date", F.lit(cfg.partition_date))
    validate_and_write(
        spark=spark,
        df=out_df,
        target_table=dlq_table,
        partition_filter=build_partition_filter({"partition_date": cfg.partition_date}),
        partition_cols=["partition_date"],
        overwrite_schema=True,
        table_location=f"s3a://{cfg.bucket}/dlq/{cfg.dlq_schema}/{cfg.target_table}",
        sync_hive=cfg.sync_hive,
        sync_secondary_catalog=True,
    )


if __name__ == "__main__":
    sfmc_clean_v2_pipeline()
