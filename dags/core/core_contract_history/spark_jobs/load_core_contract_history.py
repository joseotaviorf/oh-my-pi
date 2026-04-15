import ast

from pyspark.sql import SparkSession, DataFrame
from pyspark.sql.utils import AnalysisException

from bietlejuice.base.spark.base_core_model_spark_job import BaseCoreModelSparkJob
from bietlejuice.base.core_models.helpers.historical_helper import HistoricalHelper
from bietlejuice.base.core_models.helpers.history_builder import HistoryBuilder
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.pipeline.dataframe_delta_table_loader_pipeline import (
    DataFrameDeltaTableLoaderPipeline,
)

JOB_NAME = "contract_history"


class CoreContractHistorySparkJob(BaseCoreModelSparkJob):
    """Builds the narrow event-log history table for the contract entity.

    Reads CDC data from the transactional layer, detects field-level changes via LAG
    windows, and writes each changed field into
    ``core_contract.contract_history`` (Airflow passes ``table_name`` from the
    ``tables_customization`` key — must match governance metadata).

    Spark job argv order (see ``BaseCoreModelSparkJob.parse_args``): ``environment``,
    ``bucket``, ``dag_name``, ``schema``, ``table_name``, ``partitions``,
    ``load_start_date``, ``load_end_date``.

    This job only MERGEs into the history Delta table. The current-state snapshot
    ``core_contract.contract`` is written by the separate ``core_contract`` DAG
    (``load_core_contract``), not by this module.
    """

    def __init__(self):
        super().__init__(JOB_NAME)

    def create_core_model(self, spark: SparkSession, args) -> DataFrame:
        """Build the contract history DataFrame from the CDC transactional layer."""
        transactional_table = self.get_config("CONTRACT_TRANSACTIONAL_TABLE")
        event_configs = self.get_config("event_configs")

        self.logger.info(
            f"m=create_core_model, "
            f"msg=Building contract history from {transactional_table}, "
            f"date_range={args.load_start_date}..{args.load_end_date}"
        )

        df = HistoricalHelper.load_transactional_data(
            spark, transactional_table, args
        )

        # HistoryBuilder caches only the narrow, repartitioned slice of the
        # source data internally. Caching the full wide source here would
        # materialise every column of the contrato table into executor memory
        # before any column projection, causing unnecessary memory and swap
        # pressure on r5a.large nodes.
        result_df = HistoryBuilder.build_history_for_columns(
            df,
            entity_name="contract",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=event_configs,
            event_type="cdc",
            event_origin=transactional_table,
        )

        # event_count = result_df.count()
        # self.logger.info(
        #     f"m=create_core_model, "
        #     f"msg=Produced {event_count} history event rows, "
        #     f"date_range={args.load_start_date}..{args.load_end_date}"
        # )
        # if event_count == 0:
        #     self.logger.warning(
        #         f"m=create_core_model, "
        #         f"msg=Zero event rows produced from {transactional_table} for "
        #         f"date_range={args.load_start_date}..{args.load_end_date}. "
        #         f"Check that the transactional table has data and that field-level "
        #         f"changes exist in this range."
        #     )

        return result_df

    def _is_target_table_empty(
        self, spark: SparkSession, full_table_name: str
    ) -> bool:
        """Check if the target Delta table is missing or has zero rows."""
        try:
            if not spark.catalog.tableExists(full_table_name):
                return True
            return spark.table(full_table_name).isEmpty()
        except AnalysisException:
            return True

    def run_pipeline(self, dataframe: DataFrame, args, spark: SparkSession) -> None:
        """Partition-scoped insert-only merge for idempotent event-log writes.

        On the first run (empty target table) the merge is skipped entirely
        and a direct overwrite is used instead, avoiding the expensive
        full-table scan that caused cluster timeouts on historical backfills.
        """
        if args.partitions is not None:
            partitions = ast.literal_eval(args.partitions)
        else:
            partitions = []

        merge_on = self.get_config("merge_on_historical", required=True)
        when_matched_update_condition = self.get_config(
            "when_matched_update_condition_historical",
            required=False,
            default=None,
        )

        table_privileges = self.setup_table_privileges(args)
        database_location = (
            f"s3a://{args.bucket}/{LayerEnum.CORE.value}/{args.schema}/"
        )

        full_table_name = f"{args.schema}.{args.table_name}"
        target_is_empty = self._is_target_table_empty(spark, full_table_name)

        if target_is_empty:
            self.logger.info(
                f"m=run_pipeline, "
                f"msg=Target table {full_table_name} is empty, "
                f"using direct write (no merge)"
            )
            effective_merge_on = None
            effective_update_condition = None
        else:
            effective_merge_on = merge_on
            effective_update_condition = when_matched_update_condition

        self.logger.info(
            f"m=run_pipeline, "
            f"msg=Loading history with merge_on={effective_merge_on}, "
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
            merge_on=effective_merge_on,
            when_matched_update_condition=effective_update_condition,
            table_privileges=table_privileges,
            spark=spark,
        )

        pipeline.run()
        self.logger.info(
            f"m=run_pipeline, "
            f"msg=History loading completed for table={args.table_name}"
        )


if __name__ == "__main__":
    job = CoreContractHistorySparkJob()
    job.run()
