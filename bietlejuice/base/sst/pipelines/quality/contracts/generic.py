from datetime import datetime, timedelta

from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from quintoandar_logger import QuintoAndarLogger

from pyspark.sql.types import StructType, StructField, StringType, IntegerType
from bietlejuice.base.sst.core.utils.common import validate_and_write


class GenericContractQualityChecks:
    def __init__(
        self,
        spark: SparkSession,
        table_name: str,
        bucket: str,
        threshold_time_hours: int = 24,
    ):
        self.spark = spark
        self.table_name = table_name
        self.threshold_time_hours = threshold_time_hours
        self.bucket = bucket
        self.logger = QuintoAndarLogger(
            f"sst.pipelines.quality.contract.generic_checks.{table_name}"
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
        self._freshness_check()

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
                "_write_timestamp": datetime.now(),
            }
        )

        if count_rows == 0:
            raise RuntimeError(
                f"Table {self.table_name} has no data in the last."
                f"{self.threshold_time_hours} hours"
            )
        self.logger.info(
            f"""
            m=generic_contract_quality_checks,
            msg=Table {self.table_name} is not empty in the last {self.threshold_time_hours} hours.
            Data has processed for the last time at {last_row_timestamp}
            """
        )
