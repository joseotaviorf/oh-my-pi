from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.sst.core.utils.common import (
    default_args,
    retrieve_spark_session,
)
from bietlejuice.base.sst.core.observability.sensors import (
    sensor_table_exists,
)
from bietlejuice.base.sst.core.observability.metrics import save_stability_metric

logger = QuintoAndarLogger("sst.pipelines.metrics.pipeline_stability")
LAYERS = ["raw", "clean"]


@logger(exclude_return=True)
@default_args(
    optional_args=[
        dict(
            name="dag_name",
            flags=["--dag_name", "--dag-name"],
            type=str,
            required=True,
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
    ]
)
def run(cfg):

    job_name = f"{cfg.dag_name}.{cfg.job_name}" if cfg.dag_name != "" else cfg.job_name
    spark = retrieve_spark_session(job_name=job_name)
    size_lst = [7, 14, 28]
    for layer in LAYERS:
        target_table = f"datalake_salesforce_{layer}.{cfg.target_table}"
        # This is to avoid failing the job for new events
        if not sensor_table_exists(spark, target_table, fail=False):
            logger.info(f"m=run, msg=Table {target_table} does not exist")
            logger.info(f"m=run, msg=Skipping stability metrics for {layer=}")
            continue
        for window_size in size_lst:
            logger.info(
                f"m=save_stability_metric, msg=Saving stability metrics for {layer=}\t{cfg.target_table}\t{window_size}"
            )
            save_stability_metric(
                spark=spark,
                bucket=cfg.bucket,
                target_table=target_table,
                partition_date=cfg.partition_date,
                partition_hour=cfg.partition_hour,
                window_size=window_size,
                env=cfg.env,
                layer=layer,
            )
            logger.info(
                f"m=save_stability_metric, msg=Stability metrics saved for {layer=}\t{cfg.target_table}\t{window_size}"
            )
    logger.info("m=save_stability_metric, msg=Pipeline completed")


if __name__ == "__main__":
    run()
