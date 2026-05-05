from bietlejuice.base.sst.pipelines.sfmc.clean import (
    sfmc_clean_pipeline,
)
from bietlejuice.base.sst.core.utils.common import (
    default_args,
    retrieve_spark_session,
)

import logging
from quintoandar_logger import QuintoAndarLogger


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
            help="Source schema (datalake_sfmc_raw).",
        ),
        dict(
            name="sync_hive",
            flags=["--sync_hive", "--sync-hive"],
            type=lambda x: x.lower() == "true",
            required=False,
            default=False,
            help="When true, calls sync_trino_table_schema from sync_metadata after writing to register or update the table in Trino's Delta catalog. Requires table_location to be set.",
        ),
    ]
)
def run(cfg):
    logging.getLogger("py4j").setLevel(logging.ERROR)
    job_name = f"{cfg.dag_name}.{cfg.job_name}"
    logger = QuintoAndarLogger(job_name)
    logger.info(f"m=run, msg=Starting events for {job_name=}")
    logger.info(f"m=run, msg=Config: {cfg=}")
    spark = retrieve_spark_session(job_name=job_name)
    logger.info("m=run, msg=Spark session retrieved")
    sfmc_clean_pipeline(spark, cfg)
    logger.info("m=run, msg=All done!")


def main():
    run()


if __name__ == "__main__":
    main()
