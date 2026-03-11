from bietlejuice.base.sst.pipelines.salesforce.salesforce_raw import salesforce_raw_pipeline 
from bietlejuice.base.sst.core.utils.common import (
    default_args,
    retrieve_spark_session
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
            name="partition_hour",
            flags=["--partition_hour", "--partition-hour"],
            type=str,
            required=True,
            help="Partition hour (HH).",
        ),
        dict(
            name="event_path",
            flags=["--event_path", "--event-path"],
            type=str,
            required=True,
            help="Path to event in S3 bucket.",
        )
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
    logger.info(f"m=run, msg=Spark session retrieved")
    salesforce_raw_pipeline(spark, cfg)

def main():
    run() 

if __name__ == "__main__":
    main()