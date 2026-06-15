from datetime import datetime, timedelta

from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import IntegerType, StringType, StructField, StructType
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.sst.core.observability.common import current_write_timestamp
from bietlejuice.base.sst.core.utils.common import (
    default_args,
    retrieve_spark_session,
    validate_and_write,
)
from bietlejuice.base.sst.core.utils.time import build_partition_time_window


class GenericContractQualityChecks:
    def __init__(
        self,
        spark: SparkSession,
        table_name: str,
        bucket: str,
        logger: QuintoAndarLogger = None,
        threshold_time_hours: int = 48,
        threshold_partition_hours: int = 24,
        partition_date: str = None,
        partition_hour: str = None,
    ):
        self.spark = spark
        self.table_name = table_name
        self.threshold_partition_hours = threshold_partition_hours
        self.threshold_time_hours = threshold_time_hours
        self.partition_date = partition_date
        self.partition_hour = partition_hour
        self.bucket = bucket
        self.logger = (
            logger
            if logger
            else QuintoAndarLogger(
                f"sst.pipelines.quality.contract.generic_checks.{table_name}"
            )
        )

        self.metric_database = "datalake_sst_metrics"
        self.quality_checks_table = f"{self.metric_database}.contract_quality_checks"
        self.quality_checks_table_location = (
            f"s3a://{self.bucket}/sst_metrics/contract_quality_checks"
        )

        self.quality_checks_schema = StructType(
            [
                StructField("metric_name", StringType(), False),
                StructField("table_name", StringType(), False),
                StructField("threshold_time_hours", IntegerType(), True),
                StructField("count_rows", IntegerType(), True),
                StructField("layer", StringType(), True),
                StructField("status", StringType(), True),
                StructField("last_row_timestamp", StringType(), True),
                StructField("_write_timestamp", StringType(), True),
            ]
        )
        self.quality_checks_data = []

    def run(self) -> None:
        self.logger.info(
            f"m=run, msg=Starting generic contract checks for {self.table_name}"
        )
        if self.partition_date and self.partition_hour:
            self._freshness_check_partition()
        # self._freshness_check()

        quality_checks_df = self.spark.createDataFrame(
            self.quality_checks_data, self.quality_checks_schema
        )

        validate_and_write(
            spark=self.spark,
            df=quality_checks_df,
            target_table=self.quality_checks_table,
            table_location=self.quality_checks_table_location,
            partition_cols=["metric_name", "table_name"],
            overwrite_schema=True,
            append=True,
            sync_hive=True,
        )
        # after logging, fail the job
        failed_metric = []
        for metric in self.quality_checks_data:
            if metric["status"] == "failed":
                failed_metric.append(metric["metric_name"])

        if len(failed_metric) > 0:
            raise ValueError(
                f"m=run, msg=Failed contract checks for {self.table_name}, failed metrics: {failed_metric}"
            )

    def _freshness_check_partition(self) -> None:
        """
        Check if the table has data in the last X hours ending at the DAG partition.
        """
        (
            window_start,
            window_end,
            partition_date_start,
            partition_hour_start,
            partition_date_end,
            partition_hour_end,
        ) = build_partition_time_window(
            self.partition_date,
            self.partition_hour,
            self.threshold_partition_hours,
        )

        self.logger.info(
            f"m=freshness_check_partition, msg=Checking if table {self.table_name} "
            f"has data from {partition_date_start} {partition_hour_start} "
            f"to {partition_date_end} {partition_hour_end} "
            f"({window_start} to {window_end})"
        )

        partition_ts = F.to_timestamp(
            F.concat(F.col("partition_date"), F.lit(" "), F.col("partition_hour")),
            "yyyy-MM-dd HH",
        )
        df_partition = self.spark.table(self.table_name).where(
            (partition_ts >= F.lit(window_start)) & (partition_ts <= F.lit(window_end))
        )
        count_rows = df_partition.count()
        last_row_timestamp = df_partition.select(F.max(F.col("ts_load"))).collect()[0][
            0
        ]
        self.quality_checks_data.append(
            {
                "metric_name": "freshness_partition",
                "table_name": self.table_name,
                "threshold_time_hours": self.threshold_partition_hours,
                "count_rows": count_rows,
                "layer": self.table_name.split(".")[0].split("_")[-1],
                "status": "success" if count_rows > 0 else "failed",
                "last_row_timestamp": last_row_timestamp,
                "_write_timestamp": current_write_timestamp(),
            }
        )

        if count_rows == 0:
            self.logger.warning(
                f"Table {self.table_name} has no data in the last "
                f"{self.threshold_time_hours} hours "
                f"(partition window {partition_date_start} {partition_hour_start} "
                f"to {partition_date_end} {partition_hour_end})"
            )
            return
        self.logger.info(
            f"""
            m=generic_contract_quality_checks,
            msg=Table {self.table_name} is not empty in the last {self.threshold_partition_hours} hours.
            Data has processed for the last time at {last_row_timestamp}
            """
        )

    def _freshness_check(self) -> None:
        """
        Check if the table has data in the last X hours.
        """

        self.logger.info(
            f"m=freshness_check, msg=Checking if table {self.table_name} has data in the last {self.threshold_time_hours} hours"
        )

        df_empty_partitions = self.spark.table(self.table_name).where(
            F.col("ts_load")
            >= F.lit(datetime.now() - timedelta(hours=self.threshold_time_hours))
        )

        count_rows = df_empty_partitions.count()
        last_row_timestamp = df_empty_partitions.select(
            F.max(F.col("ts_load"))
        ).collect()[0][0]

        self.quality_checks_data.append(
            {
                "metric_name": "freshness",
                "table_name": self.table_name,
                "threshold_time_hours": self.threshold_time_hours,
                "count_rows": count_rows,
                "layer": self.table_name.split(".")[0].split("_")[-1],
                "status": "success" if count_rows > 0 else "failed",
                "last_row_timestamp": last_row_timestamp,
                "_write_timestamp": current_write_timestamp(),
            }
        )

        if count_rows == 0:
            self.logger.warning(
                f"Table {self.table_name} has no data in the last {self.threshold_time_hours} hours"
            )
            return
        self.logger.info(
            f"""
            m=generic_contract_quality_checks,
            msg=Table {self.table_name} is not empty in the last {self.threshold_time_hours} hours.
            Data has processed for the last time at {last_row_timestamp}
            """
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
            name="threshold_partition_hours",
            flags=["--threshold_partition_hours", "--threshold-partition-hours"],
            type=int,
            required=False,
            default=24,
            help="Window in hours for partition_date/partition_hour freshness check.",
        ),
        dict(
            name="threshold_time_hours",
            flags=["--threshold_time_hours", "--threshold-time-hours"],
            type=int,
            required=False,
            default=48,
            help="Window in hours for ts_load freshness check.",
        ),
    ]
)
def run(cfg):
    job_name = f"{cfg.dag_name}.{cfg.job_name}"
    logger = QuintoAndarLogger(
        f"sst.pipelines.quality.contract.generic_checks.{job_name}"
    )
    logger.info(f"m=run, msg=Starting generic contract quality checks for {job_name=}")
    spark = retrieve_spark_session(job_name=job_name)
    table_name = f"{cfg.target_schema}.{cfg.target_table}"
    bucket = cfg.bucket
    checks = GenericContractQualityChecks(
        spark=spark,
        partition_date=cfg.partition_date,
        partition_hour=cfg.partition_hour,
        table_name=table_name,
        bucket=bucket,
        logger=logger,
        threshold_partition_hours=cfg.threshold_partition_hours,
        threshold_time_hours=cfg.threshold_time_hours,
    )
    checks.run()
    logger.info("m=run, msg=Generic contract quality checks completed")


if __name__ == "__main__":
    run()
