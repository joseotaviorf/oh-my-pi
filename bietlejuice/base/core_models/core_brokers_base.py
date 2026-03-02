import ast

from pyspark.sql import SparkSession, DataFrame
from pyspark.sql.functions import (
    col,
    dayofmonth,
    lit,
    month,
    row_number,
    year,
)
from pyspark.sql.window import Window

from bietlejuice.base.spark.base_core_model_spark_job import BaseCoreModelSparkJob
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.pipeline.dataframe_delta_table_loader_pipeline import (
    DataFrameDeltaTableLoaderPipeline,
)

JOB_NAME = "core_brokers"


class CoreBrokersBaseSparkJob(BaseCoreModelSparkJob):
    """Shared base for all core_brokers Spark jobs.

    Provides reusable helpers for data loading, partition columns,
    is_current flag computation, and pipeline execution that are
    common across the brokers and brokers_product jobs.
    """

    def __init__(self):
        super().__init__(JOB_NAME)

    # ── data loading ────────────────────────────────────────────────

    def _load_data(self, spark, table_name, args, apply_date_filter=False):
        """Load and optionally filter data from a source table.

        Args:
            spark: SparkSession instance
            table_name: Fully qualified table name
            args: Job arguments (environment, bucket, dates, etc.)
            apply_date_filter: Apply incremental date filter on ts_updated

        Returns:
            DataFrame with loaded data
        """
        df = spark.read.table(table_name)

        if (
            apply_date_filter
            and args.load_start_date is not None
            and args.load_start_date != ""
            and args.load_end_date is not None
            and args.load_end_date != ""
        ):
            df = df.filter(
                (
                    col("ts_updated").cast("date")
                    >= lit(args.load_start_date).cast("date")
                )
                & (
                    col("ts_updated").cast("date")
                    <= lit(args.load_end_date).cast("date")
                )
            )

        return df

    # ── column helpers ──────────────────────────────────────────────

    def _add_partition_columns(self, df, source_col):
        """Add year/month/day partition columns derived from *source_col*."""
        return (
            df.withColumn("year", year(col(source_col)))
            .withColumn("month", month(col(source_col)))
            .withColumn("day", dayofmonth(col(source_col)))
        )

    def _add_is_current(self, df, partition_key):
        """Add ``is_current`` boolean: True for the latest transaction per entity.

        Uses a window partitioned by *partition_key* and ordered by
        ``ts_database_transaction DESC``; the first row gets ``True``.
        """
        window = Window.partitionBy(partition_key).orderBy(
            col("ts_database_transaction").desc()
        )
        return df.withColumn("is_current", (row_number().over(window) == 1))

    # ── pipeline execution ──────────────────────────────────────────

    def _run_pipeline_with_config(
        self,
        dataframe: DataFrame,
        args,
        spark: SparkSession,
        merge_on_key: str,
        update_condition_key: str,
    ) -> None:
        """Run the delta table loader pipeline with explicit config keys.

        Args:
            dataframe: DataFrame to load
            args: Parsed command line arguments
            spark: SparkSession instance
            merge_on_key: Config key for the merge columns
            update_condition_key: Config key for the update condition
        """
        if args.partitions is not None:
            partitions = ast.literal_eval(args.partitions)
        else:
            partitions = []

        merge_on = self.get_config(merge_on_key, required=True)
        when_matched_update_condition = self.get_config(
            update_condition_key, required=False, default=None
        )

        table_privileges = self.setup_table_privileges(args)
        database_location = f"s3a://{args.bucket}/{LayerEnum.CORE.value}/{args.schema}/"

        self.logger.info(
            f"m=_run_pipeline_with_config, "
            f"msg=Loading data with merge_on={merge_on}, "
            f"table_name={args.table_name}"
        )

        pipeline = DataFrameDeltaTableLoaderPipeline(
            database_name=args.schema,
            table_name=args.table_name,
            database_location=database_location,
            layer=LayerEnum.CORE.value,
            dataframe=dataframe,
            partitions=partitions,
            target_database_name=args.schema,
            target_database_location=database_location,
            merge_on=merge_on,
            when_matched_update_condition=when_matched_update_condition,
            table_privileges=table_privileges,
            spark=spark,
        )

        pipeline.run()
        self.logger.info(
            f"m=_run_pipeline_with_config, "
            f"msg=Data loading completed for table={args.table_name}"
        )
