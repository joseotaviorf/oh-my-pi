from bietlejuice.base.sst.pipelines.quality.contracts.generic import (
    GenericContractQualityChecks,
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
            help="Partition date (YYYY-MM-DD); Required by DAG template.",
        ),
        dict(
            name="partition_hour",
            flags=["--partition_hour", "--partition-hour"],
            type=str,
            required=True,
            help="Partition hour (HH); Required by DAG template.",
        ),
        dict(
            name="bucket",
            flags=["--bucket"],
            type=str,
            required=True,
            help="S3 Bucket Name.",
        ),
        dict(
            name="threshold_time_hours",
            flags=["--threshold_time_hours", "--threshold-time-hours"],
            type=int,
            required=False,
            default=24,
            help="Window in hours for ts_load freshness check.",
        ),
    ]
)

def run(cfg):
    logging.getLogger("py4j").setLevel(logging.ERROR)
    job_name = f"{cfg.dag_name}.{cfg.job_name}"
    logger = QuintoAndarLogger(job_name)
    logger.info(f"m=run, msg=Starting generic contract quality checks for {job_name=}")
    spark = retrieve_spark_session(job_name=job_name)
    table_name = f"{cfg.target_schema}.{cfg.target_table}"
    bucket = cfg.bucket
    checks = GenericContractQualityChecks(
        spark=spark,
        table_name=table_name,
        bucket=bucket,
        threshold_time_hours=cfg.threshold_time_hours,
    )
    checks.run()
    logger.info("m=run, msg=Generic contract quality checks completed")


if __name__ == "__main__":
    run()
