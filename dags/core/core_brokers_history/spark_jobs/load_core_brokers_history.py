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

# Same product scope as ``load_core_brokers._process_company_product`` (3P rent/sale).
THREE_P_BROKER_PRODUCT_IDS: Tuple[int, ...] = (27, 30)

# Output table_name -> (entity_name for HistoryBuilder, use composite PK column)
_TABLE_ENTITY_AND_COMPOSITE: Dict[str, Tuple[str, bool]] = {
    "brokers_history": ("company", False),
    "broker_products_history": ("company_product", True),
    "broker_tiers_history": ("company_product_tier", True),
}

_COMPOSITE_KEY_COL = "_history_pk"

# HistoryBuilder emits id_company_product / id_company_product_tier from _history_pk
# (id_company||id_product). Post-processing splits these and replaces sk_core_* with
# sk_company_product = concat(id_company, id_product).
_COMPOSITE_ID_SPLIT_PATTERN = r"\|\|"


class CoreBrokersHistorySparkJob(BaseCoreModelSparkJob):
    """Narrow CDC field-level history for broker-scoped company and product tables.

    Writes ``core_brokers.brokers_history``, ``broker_products_history``, and
    ``broker_tiers_history``. Product and tier pipelines only include rows whose
    ``id_product`` is in :data:`THREE_P_BROKER_PRODUCT_IDS`, matching
    ``load_core_brokers``. Company history is restricted to companies that appear
    in ``company_product`` CDC for those products in the same load window.
    Composite primary keys use a synthetic ``_history_pk`` column for LAG
    partitioning (``HistoryBuilder`` single-column contract). Product and tier
    outputs expose ``id_company``, ``id_product``, and ``sk_company_product``
    (concat of the two ids); rows with null or blank ``value`` are dropped.
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
        if args.table_name == "brokers_history":
            df = self._semi_join_companies_with_three_p_products(spark, df, args)

        df = self._normalize_tier_tracked_column(df, args.table_name)
        df = self._align_transactional_fk_columns(df, args.table_name)
        df = self._filter_three_p_product_rows(df, args.table_name)
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

        result_df = self._filter_value_filled(result_df)
        result_df = self._reshape_composite_history_output(result_df, args.table_name)

        return result_df

    def _semi_join_companies_with_three_p_products(
        self, spark: SparkSession, company_df: DataFrame, args
    ) -> DataFrame:
        """Keep only company CDC rows for companies with product 27 or 30 in-window."""
        cp_table = self.get_config(
            "BROKER_PRODUCTS_HISTORY_TRANSACTIONAL_TABLE", required=True
        )
        cp_df = HistoricalHelper.load_transactional_data(spark, cp_table, args)
        cp_df = self._align_transactional_fk_columns(
            cp_df, "broker_products_history"
        )
        cp_df = cp_df.filter(
            F.col("id_product").cast("long").isin(list(THREE_P_BROKER_PRODUCT_IDS))
        )
        allowed = (
            cp_df.select(F.col("id_company").cast("string").alias("_sk_company"))
            .distinct()
        )
        return company_df.join(
            allowed,
            F.col("id").cast("string") == F.col("_sk_company"),
            "left_semi",
        ).drop("_sk_company")

    def _filter_three_p_product_rows(
        self, df: DataFrame, table_name: str
    ) -> DataFrame:
        if table_name not in ("broker_products_history", "broker_tiers_history"):
            return df
        return df.filter(
            F.col("id_product").cast("long").isin(list(THREE_P_BROKER_PRODUCT_IDS))
        )

    def _normalize_tier_tracked_column(
        self, df: DataFrame, table_name: str
    ) -> DataFrame:
        """Align tier column with ``broker_tiers_history_event_configs``.

        YAML uses ``tracked_col: tier_id`` and ``target_col: id_tier`` (contract-style
        mapping). Some CDC snapshots expose ``id_tier`` instead of ``tier_id``; rename
        so ``HistoryBuilder`` LAG runs on ``tier_id``.
        """
        if table_name != "broker_tiers_history":
            return df
        if "tier_id" not in df.columns and "id_tier" in df.columns:
            return df.withColumnRenamed("id_tier", "tier_id")
        return df

    def _align_transactional_fk_columns(
        self, df: DataFrame, table_name: str
    ) -> DataFrame:
        """Map physical CDC FK names to core naming (id_company, id_product).

        Mirrors the transactional FK renames in ``load_core_brokers_product`` for
        ``datalake_company_transactional`` tables that still expose
        ``company_id`` / ``product_id``.
        """
        if table_name not in ("broker_products_history", "broker_tiers_history"):
            return df

        out = df
        if "id_company" not in out.columns and "company_id" in out.columns:
            out = out.withColumnRenamed("company_id", "id_company")
        if "id_product" not in out.columns and "product_id" in out.columns:
            out = out.withColumnRenamed("product_id", "id_product")
        return out

    def _filter_value_filled(self, df: DataFrame) -> DataFrame:
        """Drop rows with null or blank ``value`` (history rows must carry a value)."""
        v = F.col("value").cast("string")
        return df.filter(
            F.col("value").isNotNull() & (F.length(F.trim(v)) > 0)
        )

    def _reshape_composite_history_output(
        self, df: DataFrame, table_name: str
    ) -> DataFrame:
        """Split composite id into id_company/id_product; set sk_company_product."""
        if table_name == "broker_products_history":
            composite_col = "id_company_product"
            sk_old = "sk_core_company_product"
        elif table_name == "broker_tiers_history":
            composite_col = "id_company_product_tier"
            sk_old = "sk_core_company_product_tier"
        else:
            return df

        parts = F.split(F.col(composite_col), _COMPOSITE_ID_SPLIT_PATTERN)
        out = (
            df.withColumn("id_company", parts.getItem(0))
            .withColumn("id_product", parts.getItem(1))
            .withColumn(
                "sk_company_product",
                F.concat(F.col("id_company"), F.col("id_product")),
            )
            .drop(composite_col, sk_old)
        )
        return out.select(
            "id_event",
            "id_company",
            "id_product",
            "sk_company_product",
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

    def _prepare_keys(self, df: DataFrame, use_composite_pk: bool) -> DataFrame:
        """Normalize PK columns and optionally add synthetic composite key.

        For composite tables, ``id_company`` and ``id_product`` must already be
        present (see ``_align_transactional_fk_columns``).
        """
        if not use_composite_pk:
            return df

        # Expect convention names after transactional alignment.
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