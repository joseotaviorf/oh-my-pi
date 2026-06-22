import ast
from typing import Any, Dict, List

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F

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
        "grain": ["id_region", "id_business_unit"],
        "entity_type": "BUSINESS_UNIT_REGION",
        "sk_col": "sk_core_business_unit_region",
        "ts_updated_col": "ts_business_unit_region_updated",
        "filter_zero_keys": True,
        "output_columns": [
            "sk_core_business_unit_region",
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
    current-state mirrors of the clean tables, reconstructed from the narrow history
    tables ``core_region.business_unit_history`` / ``business_unit_region_history``.

    Attributes and ``ts_created`` are pivoted by ``CurrentStateBuilder`` (latest value
    per ``(grain, event_name)`` by ``ts_transaction`` — the current state, verified to
    match clean). ``ts_updated`` is derived as ``MAX(ts_transaction)`` per grain (CDC
    commit time, not the source ``updated_at``). For ``business_unit_region`` the ``(0,0)``
    / null-key sentinel rows are filtered out before building.
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
            history_df = self._filter_valid_keys(history_df, grain)

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

        # Surrogate key on the (string) history grain so it matches the history table's
        # sk basis (sha256 of entity_type || grain), then cast the grain to bigint to
        # align with clean / core_region.region.
        result = SurrogateKeysHelper.generate_surrogate_key(
            result, spec["entity_type"], id_column=grain
        ).withColumnRenamed("surrogate_key", spec["sk_col"])

        for grain_col in grain:
            result = result.withColumn(grain_col, F.col(grain_col).cast("long"))

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
