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

_SUPPORTED_TABLES = {"business_unit_region_history", "business_unit_history"}

_BUR_OUTPUT_COLUMNS = [
    "id_event",
    "id_business_unit_region",
    "sk_core_business_unit_region",
    "id_region",
    "id_business_unit",
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
]


class CoreRegionHistorySparkJob(BaseCoreModelSparkJob):
    """Narrow CDC field-level history for Hub Services hub/region tables.

    Writes ``core_region.business_unit_region_history`` and
    ``core_region.business_unit_history`` from
    ``datalake_hub_services_transactional.*``.

    ``business_unit_region_history`` uses the transactional junction ``id`` as the
    entity key (``id_business_unit_region``), producing 15 columns: the standard
    13-column base plus denormalized ``id_region`` and ``id_business_unit`` for
    pipeline joins. Surrogate key: ``sk_core_business_unit_region``.

    ``business_unit_history`` uses the simple ``id`` PK of the
    ``business_unit`` table, tracking 6 hub attribute columns in the standard
    13-column event log. ``HistoryBuilder`` emits ``id_business_unit`` and
    ``sk_core_business_unit`` directly (no post-processing rename needed).
    """

    def __init__(self):
        super().__init__(JOB_NAME)

    def create_core_model(self, spark: SparkSession, args: Any) -> DataFrame:
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
        """Build business_unit_region_history using transactional junction ``id``.

        Entity grain is the junction row (``id`` → ``id_business_unit_region``),
        aligned with clean/aud. ``id_region`` and ``id_business_unit`` are
        denormalized onto every event row for joins.
        """
        if "id_business_unit" not in df.columns and "business_unit_id" in df.columns:
            df = df.withColumnRenamed("business_unit_id", "id_business_unit")
        if "id_region" not in df.columns and "region_id" in df.columns:
            df = df.withColumnRenamed("region_id", "id_region")

        df = self._filter_valid_junction_keys(df)

        fk_lookup = self._build_bur_fk_lookup(df)

        result = HistoryBuilder.build_history_for_columns(
            df,
            entity_name="business_unit_region",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=event_configs,
            event_type="cdc",
            event_origin=transactional_table,
        )

        result = self._filter_value_filled(result)

        result = result.join(
            fk_lookup,
            on=["id_business_unit_region", "ts_transaction"],
            how="left",
        )

        return result.select(*_BUR_OUTPUT_COLUMNS)

    @staticmethod
    def _build_bur_fk_lookup(df: DataFrame) -> DataFrame:
        """One denormalized FK row per junction id and transaction timestamp.

        Uses the same CDC canonicalization as ``HistoryBuilder`` so a left join
        cannot duplicate history rows when several raw CDC rows share
        ``(id, ts_database_transaction)`` with conflicting FK columns.
        """
        tie_breaker_columns = HistoryBuilder._resolve_tie_breaker_columns(df, None)
        lookup_cols = list(
            dict.fromkeys(
                ["id", "ts_database_transaction", "id_region", "id_business_unit"]
                + tie_breaker_columns
            )
        )
        fk_source = df.select(*[F.col(c) for c in lookup_cols])
        fk_canonical = HistoryBuilder._canonicalize_to_one_row_per_timestamp(
            fk_source,
            id_col="id",
            ts_col="ts_database_transaction",
            tie_breaker_columns=tie_breaker_columns,
        )
        return fk_canonical.select(
            F.col("id").cast("string").alias("id_business_unit_region"),
            F.col("ts_database_transaction").alias("ts_transaction"),
            F.col("id_region").cast("string").alias("id_region"),
            F.col("id_business_unit").cast("string").alias("id_business_unit"),
        )

    @staticmethod
    def _filter_valid_junction_keys(df: DataFrame) -> DataFrame:
        """Drop sentinel/null junction rows (e.g. region_id=0, business_unit_id=0)."""
        id_col = F.col("id").cast("string")
        region_col = F.col("id_region").cast("string")
        bu_col = F.col("id_business_unit").cast("string")
        return df.filter(
            id_col.isNotNull()
            & (id_col != "0")
            & region_col.isNotNull()
            & (region_col != "0")
            & bu_col.isNotNull()
            & (bu_col != "0")
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
        database_location = f"s3a://{args.bucket}/{LayerEnum.CORE.value}/{args.schema}/"

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
            f"m=run_pipeline, msg=History loading completed for table={args.table_name}"
        )


if __name__ == "__main__":
    job = CoreRegionHistorySparkJob()
    job.run()
