"""SFMC raw layer for the file-based (SFTP) ingestion.

SFMC delivers one plain CSV per (delivery type, team, day), with a fixed key:
``{de_type}_{team_name}_{partition_date}.csv``. Each delivery type becomes its
own Delta table in the target schema, named after the delivery type. Because
the key is fully determined by these inputs, the pipeline builds the exact path
per delivery type instead of listing the bucket to discover it — no S3 SDK is
used anywhere, only Spark's own reader (``domains/sfmc/raw/io.py``).

One run loads one team, and **the team is what the target schema identifies**
(``datalake_sfmc_{team_name}_raw``). Since the table name carries only the
delivery type, two teams pointed at the same schema would write the same table
and the second run would replace the first — the day partition is overwritten,
not appended. Keeping a schema per team is what keeps them isolated, and it
also scopes the S3 location and the ``source_table`` recorded in the metrics.
Nothing here cross-checks ``--target_schema`` against ``--team_name``, so a DAG
that pairs them wrong lands one team's file in another team's schema silently.

Flow, for one ``partition_date`` and each delivery type:

1. build the exact CSV path;
2. read it, treating a missing file (SFMC has not dropped it yet) as a quiet
   skip rather than an error;
3. write the day partition and record its row count as a volume metric.

Column names are kept exactly as SFMC delivered them: raw is a faithful landing
of the file, and any renaming happens in the clean layer.

The write is an idempotent day overwrite (``replaceWhere`` on
``partition_date``) with schema evolution, so a rerun replaces the day and new
SFMC columns are added to the table. A column whose type changed in a way Delta
cannot reconcile fails the write on purpose, rather than silently dropping data.
"""

from pyspark.sql import functions as F
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.sst.core.observability.metrics import save_volume_metric
from bietlejuice.base.sst.core.utils.common import (
    build_partition_filter,
    default_args,
    retrieve_spark_session,
    validate_and_write,
)
from bietlejuice.base.sst.domains.sfmc.raw.io import build_csv_path, read_csv_if_exists

logger = QuintoAndarLogger("sst.pipelines.sfmc.raw_v2")

DEFAULT_SOURCE_PREFIX = "raw/sfmc/tracking-data"
TS_LOAD_FORMAT = "yyyy-MM-dd HH:mm:ss"
VOLUME_METRIC_NAME = "sfmc_raw_volume"


def _split_de_types(raw_value):
    # dict.fromkeys dedupes while keeping order, so a duplicated --de_types
    # entry does not write the same table twice in one run.
    return list(
        dict.fromkeys(value.strip() for value in raw_value.split(",") if value.strip())
    )


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
            name="bucket",
            flags=["--bucket"],
            type=str,
            required=True,
            help="S3 Bucket Name.",
        ),
        dict(
            name="partition_date",
            flags=["--partition_date", "--partition-date"],
            type=str,
            required=True,
            help="Partition date (YYYY-MM-DD).",
        ),
        dict(
            name="team_name",
            flags=["--team_name", "--team-name"],
            type=str,
            required=True,
            help="SFMC team name segment in the delivered file name.",
        ),
        dict(
            name="de_types",
            flags=["--de_types", "--de-types"],
            type=str,
            required=True,
            help="Comma-separated delivery types to load, one raw table each. "
            "E.g: send,return,template",
        ),
        dict(
            name="source_prefix",
            flags=["--source_prefix", "--source-prefix"],
            type=str,
            required=False,
            default=DEFAULT_SOURCE_PREFIX,
            help="Bucket prefix where SFMC delivers the CSV files.",
        ),
        dict(
            name="table_prefix",
            flags=["--table_prefix", "--table-prefix"],
            type=str,
            required=False,
            default="",
            help="Prefix prepended to every de_type to form the table name. "
            "E.g: tracking_",
        ),
        dict(
            name="csv_delimiter",
            flags=["--csv_delimiter", "--csv-delimiter"],
            type=str,
            required=False,
            default=",",
            help="CSV field delimiter.",
        ),
        dict(
            name="csv_encoding",
            flags=["--csv_encoding", "--csv-encoding"],
            type=str,
            required=False,
            default="UTF-8",
            help="CSV file encoding.",
        ),
    ]
)
def sfmc_raw_v2_pipeline(cfg):
    job_name = f"{cfg.dag_name}.{cfg.job_name}"
    logger.info(f"m=sfmc_raw_v2_pipeline, cfg: {cfg}")
    spark = retrieve_spark_session(job_name=job_name)

    de_types = _split_de_types(cfg.de_types)
    if not de_types:
        raise ValueError(
            "m=sfmc_raw_v2_pipeline, msg=de_types must name at least one "
            f"delivery type, de_types={cfg.de_types!r}"
        )

    source_prefix = f"s3a://{cfg.bucket}/{cfg.source_prefix.strip('/')}"
    partition_filter = build_partition_filter({"partition_date": cfg.partition_date})
    ts_load = F.date_format(F.current_timestamp(), TS_LOAD_FORMAT)

    delivered_count = 0
    failed_types = []
    for de_type in de_types:
        table_name = f"{cfg.table_prefix}{de_type}"
        target_table = f"{cfg.target_schema}.{table_name}"
        csv_path = build_csv_path(
            source_prefix, de_type, cfg.team_name, cfg.partition_date
        )
        try:
            raw_df = read_csv_if_exists(
                spark=spark,
                csv_path=csv_path,
                delimiter=cfg.csv_delimiter,
                encoding=cfg.csv_encoding,
            )
            # SFMC not having dropped a file yet is an expected daily state,
            # not a failure.
            if raw_df is None:
                continue
            delivered_count += 1

            raw_final = (
                raw_df.withColumn("source_file", F.input_file_name())
                .withColumn("ts_load", ts_load)
                .withColumn("partition_date", F.lit(cfg.partition_date))
            )

            validate_and_write(
                spark=spark,
                df=raw_final,
                target_table=target_table,
                partition_filter=partition_filter,
                partition_cols=["partition_date"],
                overwrite_schema=True,
                table_location=f"s3a://{cfg.bucket}/raw/{cfg.target_schema}/{table_name}",
                sync_secondary_catalog=True,
            )
            logger.info(
                "m=sfmc_raw_v2_pipeline, msg=Raw table written, "
                f"target_table={target_table}, csv_path={csv_path}"
            )

            save_volume_metric(
                spark=spark,
                df=raw_final,
                grain=["partition_date"],
                metric_name=VOLUME_METRIC_NAME,
                table_name=target_table,
                env=cfg.env,
                layer="raw",
                partition_cols=["partition_date"],
                table_location=f"s3a://{cfg.bucket}/sst_metrics/{VOLUME_METRIC_NAME}",
            )
        except Exception as error:
            # One delivery type failing does not hold back the others: the
            # healthy extracts still land, and the job still ends in error so
            # Airflow retries. Retrying is safe because every write replaces
            # its own day partition.
            logger.error(
                "m=sfmc_raw_v2_pipeline, msg=Failed to load delivery type, "
                f"de_type={de_type}, target_table={target_table}, error={error}"
            )
            failed_types.append(de_type)

    if failed_types:
        raise RuntimeError(
            "m=sfmc_raw_v2_pipeline, "
            f"msg={len(failed_types)} of {len(de_types)} delivery types failed "
            f"to load, failed_types={failed_types}"
        )

    if delivered_count == 0:
        logger.warning(
            "m=sfmc_raw_v2_pipeline, msg=No delivery type had a file for this "
            f"date, source_prefix={source_prefix}, team_name={cfg.team_name}, "
            f"partition_date={cfg.partition_date}, de_types={de_types}"
        )
        return

    logger.info("m=sfmc_raw_v2_pipeline, msg=Pipeline completed")


if __name__ == "__main__":
    sfmc_raw_v2_pipeline()
