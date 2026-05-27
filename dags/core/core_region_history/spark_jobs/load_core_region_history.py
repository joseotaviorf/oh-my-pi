import ast
from typing import Any, Dict, List

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F
from pyspark.sql.utils import AnalysisException

from bietlejuice.base.core_models.helpers.historical_helper import HistoricalHelper
from bietlejuice.base.core_models.helpers.history_builder import HistoryBuilder
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark.base_core_model_spark_job import BaseCoreModelSparkJob
from bietlejuice.pipeline.dataframe_delta_table_loader_pipeline import (
    DataFrameDeltaTableLoaderPipeline,
)

JOB_NAME = "region_history"

_COMPOSITE_KEY_COL = "_business_unit_region_pk"
_COMPOSITE_ID_SPLIT_PATTERN = r"\|\|"

_SUPPORTED_TABLES = {"business_unit_region_history", "business_unit_history"}


class CoreRegionHistorySparkJob(BaseCoreModelSparkJob):
    """Narrow CDC field-level history for Hub Services hub/region tables.

    Writes ``core_region.business_unit_region_history`` and
    ``core_region.business_unit_history`` from
    ``datalake_hub_services_transactional.*``.

    ``business_unit_region_history`` uses a composite entity key
    (``id_region||id_business_unit``) to track changes to region-hub
    associations, producing 14 columns: the standard 13-column base with
    ``id_business_unit_region`` replaced by the split ``id_region`` and
    ``id_business_unit`` columns. Surrogate key: ``sk_core_business_unit_region``.

    ``business_unit_history`` uses the simple ``id`` PK of the
    ``business_unit`` table, tracking 6 hub attribute columns in the standard
    13-column event log. ``HistoryBuilder`` emits ``id_business_unit`` and
    ``sk_core_business_unit`` directly (no post-processing rename needed).
    """

    def __init__(self):
        super().__init__(JOB_NAME)

    def create_core_model(self, spark: SparkSession, args) -> DataFrame:
        if args.table_name not in _SUPPORTED_TABLES:
            raise ValueError(
                f"Unsupported table_name={args.table_name!r} for core_region_history"
            )

        transactional_table = self._transactional_table_for(args.table_name)
        event_configs = self._event_configs_for(args.table_name)

        self.logger.info(
            f"m=create_core_model, "
            f"msg=Building {args.table_name} from {transactional_table}, "
            f"date_range={args.load_start_date}..{args.load_end_date}"
        )

        df = HistoricalHelper.load_transactional_data(spark, transactional_table, args)

        if args.table_name == "business_unit_region_history":
            return self._build_business_unit_region_history(
                df, event_configs, transactional_table
            )
        else:
            return self._build_business_unit_history(
                df, event_configs, transactional_table
            )

    def _build_business_unit_region_history(
        self,
        df: DataFrame,
        event_configs: List[Dict[str, Any]],
        transactional_table: str,
    ) -> DataFrame:
        """Build business_unit_region_history using composite region-hub key.

        The transactional table exposes FK columns as ``business_unit_id`` and
        ``region_id``. These are renamed to core conventions before building the
        composite entity key ``id_region||id_business_unit`` passed to
        ``HistoryBuilder`` as a single-column id.
        """
        if "id_business_unit" not in df.columns and "business_unit_id" in df.columns:
            df = df.withColumnRenamed("business_unit_id", "id_business_unit")
        if "id_region" not in df.columns and "region_id" in df.columns:
            df = df.withColumnRenamed("region_id", "id_region")

        df = df.withColumn(
            _COMPOSITE_KEY_COL,
            F.concat_ws(
                "||",
                F.col("id_region").cast("string"),
                F.col("id_business_unit").cast("string"),
            ),
        )

        result = HistoryBuilder.build_history_for_columns(
            df,
            entity_name="business_unit_region",
            id_col=_COMPOSITE_KEY_COL,
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=event_configs,
            event_type="cdc",
            event_origin=transactional_table,
        )

        result = self._filter_value_filled(result)
        return self._reshape_bur_history_output(result)

    def _reshape_bur_history_output(self, df: DataFrame) -> DataFrame:
        """Split composite id_business_unit_region → id_region + id_business_unit."""
        parts = F.split(F.col("id_business_unit_region"), _COMPOSITE_ID_SPLIT_PATTERN)
        return (
            df.withColumn("id_region", parts.getItem(0))
            .withColumn("id_business_unit", parts.getItem(1))
            .drop("id_business_unit_region")
            .select(
                "id_event",
                "id_region",
                "id_business_unit",
                "sk_core_business_unit_region",
                "event_name",
                "event_type",
                "value",
                "payload",
                "ts_transaction",
                "event_origin",
                "ts_load",
                "year",
                "month",
                "day",
            )
        )

    def _build_business_unit_history(
        self,
        df: DataFrame,
        event_configs: List[Dict[str, Any]],
        transactional_table: str,
    ) -> DataFrame:
        """Build business_unit_history using the simple ``id`` PK."""
        result = HistoryBuilder.build_history_for_columns(
            df,
            entity_name="business_unit",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=event_configs,
            event_type="cdc",
            event_origin=transactional_table,
        )

        result = self._filter_value_filled(result)
        return result.select(
            "id_event",
            "id_business_unit",
            "sk_core_business_unit",
            "event_name",
            "event_type",
            "value",
            "payload",
            "ts_transaction",
            "event_origin",
            "ts_load",
            "year",
            "month",
            "day",
        )

    def _filter_value_filled(self, df: DataFrame) -> DataFrame:
        """Drop rows with null or blank ``value`` (history rows must carry a value)."""
        v = F.col("value").cast("string")
        return df.filter(F.col("value").isNotNull() & (F.length(F.trim(v)) > 0))

    def _transactional_table_for(self, table_name: str) -> str:
        key = f"{table_name.upper()}_TRANSACTIONAL_TABLE"
        return self.get_config(key, required=True)

    def _event_configs_for(self, table_name: str) -> List[Dict[str, Any]]:
        key = f"{table_name}_event_configs"
        return self.get_config(key, required=True)

    def _is_target_table_empty(self, spark: SparkSession, full_table_name: str) -> bool:
        try:
            if not spark.catalog.tableExists(full_table_name):
                return True
            return spark.table(full_table_name).isEmpty()
        except AnalysisException:
            return True

    def run_pipeline(self, dataframe: DataFrame, args, spark: SparkSession) -> None:
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
    job = CoreRegionHistorySparkJob()
    job.run()
