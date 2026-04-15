import ast
from typing import Any, Dict, List, Tuple

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F

from bietlejuice.base.core_models.helpers.historical_helper import HistoricalHelper
from bietlejuice.base.core_models.helpers.history_builder import HistoryBuilder
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark.base_core_model_spark_job import BaseCoreModelSparkJob
from bietlejuice.pipeline.dataframe_delta_table_loader_pipeline import (
    DataFrameDeltaTableLoaderPipeline,
)

JOB_NAME = "brokers_history"

# Output table_name -> (entity_name for HistoryBuilder, use composite PK column)
_TABLE_ENTITY_AND_COMPOSITE: Dict[str, Tuple[str, bool]] = {
    "company_history": ("company", False),
    "company_product_history": ("company_product", True),
    "company_product_tier_history": ("company_product_tier", True),
}

_COMPOSITE_KEY_COL = "_history_pk"


class CoreBrokersHistorySparkJob(BaseCoreModelSparkJob):
    """Narrow CDC field-level history for company-related transactional tables.

    Writes to ``core_brokers.company_history``, ``company_product_history``, and
    ``company_product_tier_history`` depending on ``table_name``. Composite
    primary keys (company + product) use a synthetic ``_history_pk`` column for
    LAG partitioning, matching :class:`HistoryBuilder` single-column contract.
    """

    def __init__(self):
        super().__init__(JOB_NAME)

    def create_core_model(self, spark: SparkSession, args) -> DataFrame:
        if args.table_name not in _TABLE_ENTITY_AND_COMPOSITE:
            raise ValueError(
                f"Unsupported table_name={args.table_name!r} for core_brokers_history"
            )

        entity_name, use_composite_pk = _TABLE_ENTITY_AND_COMPOSITE[args.table_name]
        transactional_table = self._transactional_table_for(args.table_name)
        event_configs = self._event_configs_for(args.table_name)

        self.logger.info(
            f"m=create_core_model, "
            f"msg=Building {args.table_name} from {transactional_table}, "
            f"date_range={args.load_start_date}..{args.load_end_date}"
        )

        df = HistoricalHelper.load_transactional_data(
            spark, transactional_table, args
        )
        df = self._normalize_tier_columns(df, args.table_name)
        df = self._prepare_keys(df, use_composite_pk)

        id_col = _COMPOSITE_KEY_COL if use_composite_pk else "id"

        result_df = HistoryBuilder.build_history_for_columns(
            df,
            entity_name=entity_name,
            id_col=id_col,
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=event_configs,
            event_type="cdc",
            event_origin=transactional_table,
        )

        return result_df

    def _normalize_tier_columns(self, df: DataFrame, table_name: str) -> DataFrame:
        """Align tier FK column name with event_configs (id_tier)."""
        if table_name != "company_product_tier_history":
            return df
        if "id_tier" not in df.columns and "tier_id" in df.columns:
            return df.withColumnRenamed("tier_id", "id_tier")
        return df

    def _prepare_keys(self, df: DataFrame, use_composite_pk: bool) -> DataFrame:
        """Normalize PK columns and optionally add synthetic composite key."""
        if not use_composite_pk:
            return df

        # Transactional layer aligns with id_company / id_product (see brokers lineage).
        for name in ("id_company", "id_product"):
            if name not in df.columns:
                raise ValueError(
                    f"Expected column {name!r} for composite PK history; "
                    f"got columns={df.columns}"
                )

        return df.withColumn(
            _COMPOSITE_KEY_COL,
            F.concat_ws(
                "||",
                F.col("id_company").cast("string"),
                F.col("id_product").cast("string"),
            ),
        )

    def _transactional_table_for(self, table_name: str) -> str:
        key = f"{table_name.upper()}_TRANSACTIONAL_TABLE"
        return self.get_config(key, required=True)

    def _event_configs_for(self, table_name: str) -> List[Dict[str, Any]]:
        key = f"{table_name}_event_configs"
        return self.get_config(key, required=True)

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

        self.logger.info(
            f"m=run_pipeline, "
            f"msg=Loading history with merge_on={merge_on}, "
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
            f"m=run_pipeline, "
            f"msg=History loading completed for table={args.table_name}"
        )


if __name__ == "__main__":
    job = CoreBrokersHistorySparkJob()
    job.run()