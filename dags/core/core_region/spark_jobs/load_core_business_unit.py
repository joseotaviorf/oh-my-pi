import ast
from typing import Any, Dict, List

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F
from pyspark.sql.window import Window

from bietlejuice.base.core_models.helpers.current_state_builder import (
    CurrentStateBuilder,
)
from bietlejuice.base.core_models.helpers.surrogate_keys import SurrogateKeysHelper
from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark.base_core_model_spark_job import BaseCoreModelSparkJob
from bietlejuice.pipeline.dataframe_delta_table_loader_pipeline import (
    DataFrameDeltaTableLoaderPipeline,
)

JOB_NAME = "core_business_unit"

# Per-table specification for the two current-state models built by this job. Each table is
# materialised from its narrow history table (produced by the core_region_history DAG) via
# CurrentStateBuilder. Both run in the same core_region DAG as independent tasks; the existing
# `region` table keeps its own load_core_region job and is untouched.
_TABLE_SPECS: Dict[str, Dict[str, Any]] = {
    "business_unit": {
        "history_table_config_key": "BUSINESS_UNIT_HISTORY_TABLE",
        "grain": ["id_business_unit"],
        "entity_type": "BUSINESS_UNIT",
        "sk_col": "sk_core_business_unit",
        "ts_updated_col": "ts_business_unit_updated",
        "filter_zero_keys": False,
        "output_columns": [
            "sk_core_business_unit",
            "id_business_unit",
            "hub_name",
            "business_context",
            "sdr_type",
            "negotiation_type",
            "lead_types",
            "operational_context",
            "ts_business_unit_created",
            "ts_business_unit_updated",
            "ts_load",
            "year",
            "month",
            "day",
        ],
    },
    "business_unit_region": {
        "history_table_config_key": "BUSINESS_UNIT_REGION_HISTORY_TABLE",
        "grain": ["id_business_unit_region"],
        "entity_type": "BUSINESS_UNIT_REGION",
        "sk_col": "sk_core_business_unit_region",
        "ts_updated_col": "ts_business_unit_region_updated",
        "filter_zero_keys": True,
        "filter_key_columns": [
            "id_business_unit_region",
            "id_region",
            "id_business_unit",
        ],
        "denormalized_fk_columns": ["id_region", "id_business_unit"],
        "pair_dedup_key_columns": ["id_region", "id_business_unit"],
        "pair_dedup_junction_col": "id_business_unit_region",
        "output_columns": [
            "sk_core_business_unit_region",
            "id_business_unit_region",
            "id_region",
            "id_business_unit",
            "business_context",
            "ts_business_unit_region_created",
            "ts_business_unit_region_updated",
            "ts_load",
            "year",
            "month",
            "day",
        ],
    },
}


class CoreBusinessUnitSparkJob(BaseCoreModelSparkJob):
    """Current-state core models for the Hub Services business_unit domain.

    Writes ``core_region.business_unit`` and ``core_region.business_unit_region`` as
    current-state tables reconstructed from the narrow history tables
    ``core_region.business_unit_history`` / ``business_unit_region_history``.

    Attributes and ``ts_created`` are pivoted by ``CurrentStateBuilder`` (latest value
    per ``(grain, event_name)`` by ``ts_transaction``). ``ts_updated`` is derived as
    ``MAX(ts_transaction)`` per grain (CDC commit time, not the source ``updated_at``).

    For ``business_unit_region`` the pipeline builds junction-level current state from
    history, then keeps one row per ``(id_region, id_business_unit)`` by selecting the
    highest ``id_business_unit_region`` (matches clean when stale CDC junction rows
    remain live). ``id_business_unit_region`` and ``sk_core_*`` reflect that winning
    junction id (same role as clean ``id``). Merge is on the region–hub pair so
    re-association replaces the pair row when the winning junction id changes.
    """

    def __init__(self):
        super().__init__(JOB_NAME)

    def create_core_model(self, spark: SparkSession, args: Any) -> DataFrame:
        if args.table_name not in _TABLE_SPECS:
            raise ValueError(
                f"Unsupported table_name={args.table_name!r} for core_business_unit"
            )

        spec = _TABLE_SPECS[args.table_name]
        grain = spec["grain"]
        history_table = self.get_config(spec["history_table_config_key"], required=True)
        event_configs = self.get_config(
            f"{args.table_name}_event_configs", required=True
        )

        self.logger.info(
            f"m=create_core_model, "
            f"msg=Building {args.table_name} current state from {history_table}, "
            f"grain={grain}"
        )

        history_df = spark.table(history_table)
        if spec["filter_zero_keys"]:
            key_cols = spec.get("filter_key_columns", grain)
            history_df = self._filter_valid_keys(history_df, key_cols)

        # Full rebuild: no load-window filter so every grain is reconstructed from the
        # complete history each run. CurrentStateBuilder pivots attributes + ts_created
        # (latest value by ts_transaction).
        current_df = CurrentStateBuilder.build_current_state(
            history_df,
            grain,
            event_configs,
        )

        ts_updated_col = spec["ts_updated_col"]
        ts_updated_df = history_df.groupBy(*grain).agg(
            F.max("ts_transaction").alias(ts_updated_col)
        )
        result = current_df.join(ts_updated_df, grain, "left")

        denormalized_fk_columns = spec.get("denormalized_fk_columns")
        if denormalized_fk_columns:
            result = self._attach_denormalized_fks(
                result, history_df, grain[0], denormalized_fk_columns
            )

        pair_dedup_keys = spec.get("pair_dedup_key_columns")
        if pair_dedup_keys:
            junction_col = spec["pair_dedup_junction_col"]
            result = self._dedupe_latest_junction_per_pair(
                result,
                pair_dedup_keys,
                junction_col,
                ts_updated_col,
            )

        # Surrogate key on the winning junction id (sha256 of entity_type || grain).
        result = SurrogateKeysHelper.generate_surrogate_key(
            result, spec["entity_type"], id_column=grain
        ).withColumnRenamed("surrogate_key", spec["sk_col"])

        bigint_cols = list(
            dict.fromkeys(grain + spec.get("denormalized_fk_columns", []))
        )
        for col_name in bigint_cols:
            result = result.withColumn(col_name, F.col(col_name).cast("long"))

        result = (
            result.withColumn("ts_load", F.current_timestamp())
            .withColumn("year", F.year(F.col(ts_updated_col)))
            .withColumn("month", F.month(F.col(ts_updated_col)))
            .withColumn("day", F.dayofmonth(F.col(ts_updated_col)))
        )

        result = result.select(*spec["output_columns"])

        self.logger.info(
            f"m=create_core_model, msg=Core model {args.table_name} created"
        )
        return result

    @staticmethod
    def _filter_valid_keys(df: DataFrame, grain: List[str]) -> DataFrame:
        """Drop sentinel rows whose grain key is null or the ``'0'`` placeholder.

        ``business_unit_region`` history carries a ``(0,0)`` junk cluster (epoch-0
        created_at) that must not enter the current state.
        """
        condition = None
        for grain_col in grain:
            col_condition = F.col(grain_col).isNotNull() & (
                F.col(grain_col) != F.lit("0")
            )
            condition = (
                col_condition if condition is None else (condition & col_condition)
            )
        return df.filter(condition)

    @staticmethod
    def _attach_denormalized_fks(
        current_df: DataFrame,
        history_df: DataFrame,
        grain_col: str,
        fk_columns: List[str],
    ) -> DataFrame:
        """Join denormalized FK columns from the latest history row per junction grain."""
        select_cols = [grain_col] + fk_columns + ["ts_transaction"]
        fk_source = history_df.select(
            *[F.col(c) for c in select_cols if c in history_df.columns]
        )
        order_by = [F.col("ts_transaction").desc()]
        window = Window.partitionBy(grain_col).orderBy(*order_by)
        fk_lookup = (
            fk_source.withColumn("_rn", F.row_number().over(window))
            .filter(F.col("_rn") == 1)
            .drop("_rn", "ts_transaction")
        )
        return current_df.join(fk_lookup, grain_col, "left")

    @staticmethod
    def _dedupe_latest_junction_per_pair(
        df: DataFrame,
        pair_key_columns: List[str],
        junction_col: str,
        ts_updated_col: str,
    ) -> DataFrame:
        """Keep one junction row per region–hub pair (matches clean live association).

        When CDC retains multiple junction ids for the same pair after re-association,
        clean keeps the newest junction id; empirically that is the highest
        ``id_business_unit_region``. ``ts_business_unit_region_updated`` breaks ties.
        """
        order_by = [
            F.col(junction_col).cast("long").desc(),
            F.col(ts_updated_col).desc(),
        ]
        window = Window.partitionBy(*pair_key_columns).orderBy(*order_by)
        return (
            df.withColumn("_pair_rn", F.row_number().over(window))
            .filter(F.col("_pair_rn") == 1)
            .drop("_pair_rn")
        )

    def run_pipeline(
        self, dataframe: DataFrame, args: Any, spark: SparkSession
    ) -> None:
        """Merge the current-state DataFrame into the target table per-table.

        Mirrors the base null-preserving merge (never overwrite a non-null target column
        with a null from source) but reads the merge key and update condition from
        table-prefixed config keys, since this DAG hosts multiple tables with distinct
        grains in one shared conf.
        """
        source_cols = dataframe.columns
        if args.partitions is not None:
            partitions = ast.literal_eval(args.partitions)
        else:
            partitions = []

        target_table_name = f"{args.schema}.{args.table_name}"
        try:
            target_cols = set(spark.table(target_table_name).columns)
        except Exception:
            target_cols = set()

        merge_on = self.get_config(f"{args.table_name}_merge_on", required=True)
        when_matched_update_condition = self.get_config(
            f"{args.table_name}_when_matched_update_condition",
            required=False,
            default=None,
        )

        overwrite_with_null = self.get_config(
            "overwrite_with_null", required=False, default=False
        )
        when_matched_operation = {}
        for col_name in source_cols:
            if col_name in target_cols and not overwrite_with_null:
                when_matched_operation[col_name] = (
                    f"CASE WHEN source.{col_name} IS NOT NULL "
                    f"THEN source.{col_name} ELSE target.{col_name} END"
                )
            else:
                when_matched_operation[col_name] = f"source.{col_name}"

        database_location = f"s3a://{args.bucket}/{LayerEnum.CORE.value}/{args.schema}/"

        write_database_name = args.schema
        write_table_name = args.table_name
        write_database_location = database_location
        if getattr(args, "target_database_name", None) and getattr(
            args, "target_table_name", None
        ):
            from bietlejuice.base.validation.target_resolver import (
                validation_database_location,
            )

            write_database_name = args.target_database_name
            write_table_name = args.target_table_name
            write_database_location = validation_database_location(
                args.bucket, args.schema
            )

        table_privileges = TablePrivileges.from_environment_default(
            f"{write_database_name}.{write_table_name}"
        )

        self.logger.info(
            f"m=run_pipeline, "
            f"msg=Loading {args.table_name} with merge_on={merge_on}, "
            f"partitions={partitions}"
        )

        pipeline = DataFrameDeltaTableLoaderPipeline(
            database_name=write_database_name,
            table_name=write_table_name,
            database_location=write_database_location,
            layer=LayerEnum.CORE.value,
            dataframe=dataframe,
            partitions=partitions,
            target_database_name=write_database_name,
            target_database_location=write_database_location,
            merge_on=merge_on,
            when_matched_update_condition=when_matched_update_condition,
            when_matched_operation=when_matched_operation,
            table_privileges=table_privileges,
            spark=spark,
        )

        pipeline.run()
        self.logger.info(
            f"m=run_pipeline, msg=Data loading completed for table={args.table_name}"
        )


if __name__ == "__main__":
    job = CoreBusinessUnitSparkJob()
    job.run()
