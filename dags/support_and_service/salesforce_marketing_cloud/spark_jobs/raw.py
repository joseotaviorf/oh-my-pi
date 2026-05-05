from bietlejuice.base.sst.core.utils.common import (
    default_args,
    retrieve_spark_session,
)
from bietlejuice.base.sst.pipelines.sfmc.raw import (
    sfmc_raw_pipeline,
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
            name="external_key",
            flags=["--external_key", "--external-key"],
            type=str,
            required=True,
            help="Object external key.",
        ),
    ]
)
def run(cfg):
    logging.getLogger("py4j").setLevel(logging.ERROR)
    logging.info(f"m=run, CFG: {cfg}")
    job_name = f"{cfg.dag_name}.{cfg.job_name}"
    logger = QuintoAndarLogger(job_name)
    logger.info(f"m=run, msg=Starting events for {job_name=}")
    logger.info(f"m=run, msg=Config: {cfg=}")
    spark = retrieve_spark_session(job_name=job_name)
    logger.info("m=run, msg=Spark session retrieved")
    sfmc_raw_pipeline(spark, cfg)


def main():
    run()


if __name__ == "__main__":
    main()
