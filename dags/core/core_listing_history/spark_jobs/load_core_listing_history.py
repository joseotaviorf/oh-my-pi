import ast
from functools import reduce
from typing import Any, Dict, List

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F
from pyspark.sql.window import Window
from pyspark.sql.utils import AnalysisException

from bietlejuice.base.core_models.helpers.historical_helper import HistoricalHelper
from bietlejuice.base.core_models.helpers.surrogate_keys import SurrogateKeysHelper
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark.base_core_model_spark_job import BaseCoreModelSparkJob
from bietlejuice.pipeline.dataframe_delta_table_loader_pipeline import (
    DataFrameDeltaTableLoaderPipeline,
)

JOB_NAME = "listing_history"

_OUTPUT_COLUMNS = [
    "id_event",
    "id_house",
    "id_house_listing",
    "business_context",
    "sk_core_listing_history",
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



class CoreListingHistorySparkJob(BaseCoreModelSparkJob):
    """Builds the narrow event-log history table for the listing entity.

    Combines three event sources into a unified timeline per
    (id_house_listing, business_context):

    1. **LBC CDC events** — field-level changes from
       ``datalake_ebdb_transactional.ListingBusinessContext``.
       Tracks ownership, publication timestamps, and (for SALE only)
       status/status_reason.

    2. **House price events** — CDC from
       ``datalake_ebdb_transactional.Imovel`` for price-related columns.
       RENT tracks ``aluguel`` as ``ev_price``; SALE tracks ``salePrice``
       as ``ev_price``. Shared columns (``valorTotal``, ``condominio``,
       ``iptu``, type columns) are tracked for both contexts.

    3. **Aux-derived events** (RENT only) — from
       ``core_listing.aux__lbc_status_version_order`` and
       ``core_listing.aux__house_listing_category``. Tracks status,
       status_reason, version, category, is_extended_rental, and
       has_termination_canceled as they evolve through the listing lifecycle.

    For LBC and price events the listing version is resolved via temporal
    join with ``aux__lbc_status_version_order`` (RENT) or fixed at 0 (SALE).

    On the first run (empty target table), the merge is skipped for a direct
    overwrite, avoiding expensive full-table scans during historical backfills.
    """

    def __init__(self):
        super().__init__(JOB_NAME)

    def create_core_model(self, spark: SparkSession, args) -> DataFrame:
        lbc_transactional_table = self.get_config("LBC_TRANSACTIONAL_TABLE")

        lbc_houses = (
            spark.read.table(lbc_transactional_table)
            .select(
                F.col("imovelId").cast("string").alias("_lbc__id_house"),
                F.col("businessContext").alias("_lbc__bc"),
            )
            .distinct()
        )
        rent_houses = (
            lbc_houses.filter(F.col("_lbc__bc") == "RENT")
            .select("_lbc__id_house")
            .distinct()
        )
        sale_houses = (
            lbc_houses.filter(F.col("_lbc__bc") == "SALE")
            .select("_lbc__id_house")
            .distinct()
        )

        aux_table = self.get_config("AUX_LBC_STATUS_VERSION_ORDER_TABLE")
        aux_df = spark.read.table(aux_table)
        version_ranges = self._build_version_ranges(aux_df)

        self.logger.info(
            f"m=create_core_model, "
            f"msg=Building listing history, "
            f"date_range={args.load_start_date}..{args.load_end_date}"
        )

        event_dfs: List[DataFrame] = []

        lbc_events = self._build_lbc_cdc_events(spark, args, version_ranges)
        event_dfs.append(lbc_events)

        price_events = self._build_price_events(
            spark, args, rent_houses, sale_houses, version_ranges
        )
        event_dfs.append(price_events)

        aux_events = self._build_aux_rent_events(spark, args, aux_df)
        event_dfs.append(aux_events)

        return reduce(DataFrame.unionByName, event_dfs)

    @staticmethod
    def _build_version_ranges(aux_df: DataFrame) -> DataFrame:
        """Collapse aux__lbc_status_version_order to version-level time ranges.

        Returns one row per (id_house, listing_version) with the earliest
        start and latest end across all status periods of that version.
        SALE listings never appear in the aux table, so they will not match
        in the temporal join and fall back to version 0.
        """
        return (
            aux_df.groupBy("id_house", "listing_version")
            .agg(
                F.min("ts_state_started").alias("_version_range__ts_start"),
                F.max("ts_state_ended").alias("_version_range__ts_end"),
            )
            .select(
                F.col("id_house").cast("string").alias("_version_range__id_house"),
                F.concat(
                    F.col("id_house").cast("string"),
                    F.lpad(F.col("listing_version").cast("string"), 3, "0"),
                ).cast("bigint").alias("_version_range__id_house_listing"),
                F.col("_version_range__ts_start"),
                F.col("_version_range__ts_end"),
            )
        )

    @staticmethod
    def _resolve_version(df: DataFrame, version_ranges: DataFrame) -> DataFrame:
        """Add ``id_house_listing`` via temporal join with version ranges.

        SALE rows always receive version 0 (``concat(id_house, "000")``).
        RENT rows are resolved via temporal join with aux version ranges;
        unmatched RENT rows are excluded (same as core_listing, which only
        includes RENT listings present in aux__lbc_status_version_order).
        """
        vr = version_ranges.alias("vr")

        joined = df.join(
            F.broadcast(vr),
            (df["id_house"] == vr["_version_range__id_house"])
            & (df["ts_database_transaction"] >= vr["_version_range__ts_start"])
            & (
                vr["_version_range__ts_end"].isNull()
                | (df["ts_database_transaction"] <= vr["_version_range__ts_end"])
            ),
            "left",
        )

        resolved = (
            joined.withColumn(
                "id_house_listing",
                F.when(
                    F.col("business_context") == "SALE",
                    F.concat(F.col("id_house"), F.lit("000")).cast("bigint"),
                ).otherwise(F.col("_version_range__id_house_listing")),
            )
            .drop(
                "_version_range__id_house",
                "_version_range__id_house_listing",
                "_version_range__ts_start",
                "_version_range__ts_end",
            )
        )

        return resolved.filter(F.col("id_house_listing").isNotNull())

    def _build_lbc_cdc_events(
        self,
        spark: SparkSession,
        args,
        version_ranges: DataFrame,
    ) -> DataFrame:
        """Build events from ListingBusinessContext transactional CDC.

        Reads directly from ``datalake_ebdb_transactional.ListingBusinessContext``
        which has native ``op_cdc`` and ``ts_database_transaction`` columns.
        Tracks ownership and publication timestamps for both RENT and SALE.
        Additionally tracks status and status_reason for SALE listings
        (RENT status comes from aux tables instead).

        Change detection partitions by (id_house, business_context) because
        the LBC entity is 1:1 with (id_house, business_context) regardless
        of listing version. The resolved ``id_house_listing`` is added for
        the output key but does not affect change detection.
        """
        lbc_transactional_table = self.get_config("LBC_TRANSACTIONAL_TABLE")
        common_configs = self.get_config("lbc_common_event_configs")
        sale_configs = self.get_config("lbc_sale_event_configs")

        df = HistoricalHelper.load_transactional_data(
            spark, lbc_transactional_table, args
        )

        df = (
            df.withColumn("id_house", F.col("imovelId").cast("string"))
            .withColumn("business_context", F.col("businessContext"))
        )

        df = self._resolve_version(df, version_ranges)

        all_configs = common_configs + sale_configs
        tracked_cols = list({ec["tracked_col"] for ec in all_configs})

        cols_to_keep = [
            "id_house",
            "id_house_listing",
            "business_context",
            "ts_database_transaction",
            "op_cdc",
        ] + tracked_cols
        df_source = df.select(*[F.col(c) for c in cols_to_keep])

        w = Window.partitionBy("id_house_listing", "business_context").orderBy(
            "ts_database_transaction"
        )
        for col_name in tracked_cols:
            df_source = df_source.withColumn(
                f"_prev_{col_name}", F.lag(F.col(col_name)).over(w)
            )

        df_source.cache()
        try:
            event_dfs: List[DataFrame] = []

            for ec in common_configs:
                events = self._detect_changes_and_emit(
                    df_source, ec, lbc_transactional_table, event_type="cdc"
                )
                event_dfs.append(events)

            sale_source = df_source.filter(
                F.col("business_context") == "SALE"
            )
            for ec in sale_configs:
                events = self._detect_changes_and_emit(
                    sale_source, ec, lbc_transactional_table, event_type="cdc"
                )
                event_dfs.append(events)

            return reduce(DataFrame.unionByName, event_dfs)
        finally:
            df_source.unpersist()

    def _build_price_events(
        self,
        spark: SparkSession,
        args,
        rent_houses: DataFrame,
        sale_houses: DataFrame,
        version_ranges: DataFrame,
    ) -> DataFrame:
        """Build events from imovel transactional CDC for price columns.

        Processes RENT and SALE separately because price maps to different
        source columns (``aluguel`` for RENT, ``salePrice`` for SALE).
        Shared columns (total_value, condo, iptu, types) are tracked
        for both contexts.

        Change detection partitions by (id_house, business_context) because
        price changes happen at the house level. The resolved
        ``id_house_listing`` is added for the output key.
        """
        house_table = self.get_config("HOUSE_TRANSACTIONAL_TABLE")
        rent_configs = self.get_config("rent_price_event_configs")
        sale_configs = self.get_config("sale_price_event_configs")

        house_df = HistoricalHelper.load_transactional_data(
            spark, house_table, args
        )

        event_dfs: List[DataFrame] = []

        rent_df = house_df.join(
            F.broadcast(rent_houses),
            house_df["id"].cast("string") == rent_houses["_lbc__id_house"],
            "inner",
        ).withColumn("business_context", F.lit("RENT"))

        rent_events = self._detect_price_changes(
            rent_df, rent_configs, house_table, version_ranges
        )
        event_dfs.append(rent_events)

        sale_df = house_df.join(
            F.broadcast(sale_houses),
            house_df["id"].cast("string") == sale_houses["_lbc__id_house"],
            "inner",
        ).withColumn("business_context", F.lit("SALE"))

        sale_events = self._detect_price_changes(
            sale_df, sale_configs, house_table, version_ranges
        )
        event_dfs.append(sale_events)

        return reduce(DataFrame.unionByName, event_dfs)

    def _detect_price_changes(
        self,
        df: DataFrame,
        event_configs: List[Dict[str, Any]],
        event_origin: str,
        version_ranges: DataFrame,
    ) -> DataFrame:
        """LAG-based change detection for house price columns."""
        tracked_cols = [ec["tracked_col"] for ec in event_configs]

        cols_to_keep = [
            "id",
            "business_context",
            "ts_database_transaction",
            "op_cdc",
        ] + tracked_cols
        df_source = df.select(*[F.col(c) for c in cols_to_keep])
        df_source = df_source.withColumnRenamed("id", "id_house").withColumn(
            "id_house", F.col("id_house").cast("string")
        )

        df_source = self._resolve_version(df_source, version_ranges)

        w = Window.partitionBy("id_house_listing", "business_context").orderBy(
            "ts_database_transaction"
        )
        for col_name in tracked_cols:
            df_source = df_source.withColumn(
                f"_prev_{col_name}", F.lag(F.col(col_name)).over(w)
            )

        df_source.cache()
        try:
            event_dfs: List[DataFrame] = []
            for ec in event_configs:
                events = self._detect_changes_and_emit(
                    df_source, ec, event_origin, event_type="cdc"
                )
                event_dfs.append(events)
            return reduce(DataFrame.unionByName, event_dfs)
        finally:
            df_source.unpersist()

    def _build_aux_rent_events(
        self,
        spark: SparkSession,
        args,
        aux_df: DataFrame,
    ) -> DataFrame:
        """Build events from aux__lbc_status_version_order and category table.

        For RENT listings only. Tracks status, status_reason, version,
        is_extended_rental, has_termination_canceled, and category.
        Uses ts_state_started as the event timestamp (when each status
        period began).

        Change detection partitions by (id_house_listing) since each
        listing version has an independent lifecycle.
        """
        aux_table = self.get_config("AUX_LBC_STATUS_VERSION_ORDER_TABLE")
        cat_table = self.get_config("AUX_HOUSE_LISTING_CATEGORY_TABLE")
        aux_configs = self.get_config("aux_event_configs")

        if self._has_date_range(args):
            aux_df = aux_df.filter(
                (
                    F.col("ts_state_started").cast("date")
                    >= F.lit(args.load_start_date).cast("date")
                )
                & (
                    F.col("ts_state_started").cast("date")
                    <= F.lit(args.load_end_date).cast("date")
                )
            )

        cat_df = spark.read.table(cat_table).select(
            F.col("id_house").cast("string").alias("_category__id_house"),
            F.col("id_house_listing").alias("_category__id_house_listing"),
            F.col("listing_category"),
        )

        aux_df = (
            aux_df.withColumn(
                "id_house", F.col("id_house").cast("string")
            )
            .withColumn("business_context", F.lit("RENT"))
            .withColumn(
                "id_house_listing",
                F.concat(
                    F.col("id_house"),
                    F.lpad(F.col("listing_version").cast("string"), 3, "0"),
                ).cast("bigint"),
            )
        )

        aux_df = aux_df.join(
            cat_df,
            (aux_df["id_house"] == cat_df["_category__id_house"])
            & (aux_df["id_house_listing"] == cat_df["_category__id_house_listing"]),
            "left",
        ).drop("_category__id_house", "_category__id_house_listing")

        # Align with core_listing: version 0 + missing category row → "NA"
        aux_df = aux_df.withColumn(
            "listing_category",
            F.when(
                (F.col("listing_version") == 0)
                & F.col("listing_category").isNull(),
                F.lit("NA"),
            ).otherwise(F.col("listing_category")),
        )

        tracked_cols = [ec["tracked_col"] for ec in aux_configs]

        cols_to_keep = [
            "id_house",
            "id_house_listing",
            "business_context",
            "ts_state_started",
        ] + tracked_cols
        aux_source = aux_df.select(
            *[F.col(c) for c in cols_to_keep]
        ).withColumnRenamed("ts_state_started", "ts_database_transaction")

        aux_source = aux_source.withColumn("op_cdc", F.lit("u"))

        w = Window.partitionBy("id_house_listing").orderBy(
            "ts_database_transaction"
        )
        for col_name in tracked_cols:
            aux_source = aux_source.withColumn(
                f"_prev_{col_name}", F.lag(F.col(col_name)).over(w)
            )

        aux_source.cache()
        try:
            event_dfs: List[DataFrame] = []
            for ec in aux_configs:
                events = self._detect_changes_and_emit(
                    aux_source, ec, aux_table, event_type="derived"
                )
                event_dfs.append(events)
            return reduce(DataFrame.unionByName, event_dfs)
        finally:
            aux_source.unpersist()

    def _detect_changes_and_emit(
        self,
        df_with_lag: DataFrame,
        event_config: Dict[str, Any],
        event_origin: str,
        event_type: str = "cdc",
    ) -> DataFrame:
        """Detect field-level changes via LAG and emit narrow events."""
        tracked_col = event_config["tracked_col"]
        target_col = event_config["target_col"]
        event_name = f"ev_{target_col}"
        prev_col = f"_prev_{tracked_col}"

        values_differ = ~F.col(tracked_col).cast("string").eqNullSafe(
            F.col(prev_col).cast("string")
        )

        # All callers keep ``op_cdc`` in the projected columns (transactional CDC
        # or ``lit("u")`` for aux). Inserts/deletes always emit; updates only
        # when the tracked value changed.
        changed = df_with_lag.filter(
            (F.col("op_cdc") == "c")
            | (F.col("op_cdc") == "d")
            | ((F.col("op_cdc") == "u") & values_differ)
        )

        return self._format_event(
            changed,
            event_name=event_name,
            value_col=tracked_col,
            ts_col="ts_database_transaction",
            event_origin=event_origin,
            event_type=event_type,
        )

    def _format_event(
        self,
        df: DataFrame,
        event_name: str,
        value_col: str,
        ts_col: str,
        event_origin: str,
        event_type: str = "cdc",
    ) -> DataFrame:
        """Shape a change-detected DataFrame into the standard output schema."""
        events = df.select(
            F.col("id_house").cast("string").alias("id_house"),
            F.col("id_house_listing"),
            F.col("business_context"),
            F.lit(event_name).alias("event_name"),
            F.lit(event_type).alias("event_type"),
            F.col(value_col).cast("string").alias("value"),
            F.lit(None).cast("string").alias("payload"),
            F.col(ts_col).alias("ts_transaction"),
            F.lit(event_origin).alias("event_origin"),
        )

        events = events.withColumn(
            "id_event",
            F.sha2(
                F.concat_ws(
                    "||",
                    F.col("id_house_listing").cast("string"),
                    F.col("business_context"),
                    F.col("event_name"),
                    F.col("ts_transaction").cast("string"),
                ),
                256,
            ),
        )

        events = SurrogateKeysHelper.generate_surrogate_key(
            events,
            "LISTING_HISTORY",
            id_column=["id_house_listing", "business_context"],
        ).withColumnRenamed("surrogate_key", "sk_core_listing_history")

        return (
            events.withColumn("ts_load", F.current_timestamp())
            .withColumn("year", F.year(F.col("ts_transaction")))
            .withColumn("month", F.month(F.col("ts_transaction")))
            .withColumn("day", F.dayofmonth(F.col("ts_transaction")))
            .select(*_OUTPUT_COLUMNS)
        )

    @staticmethod
    def _has_date_range(args) -> bool:
        return (
            args.load_start_date is not None
            and args.load_start_date != ""
            and args.load_end_date is not None
            and args.load_end_date != ""
        )

    def _is_target_table_empty(
        self, spark: SparkSession, full_table_name: str
    ) -> bool:
        try:
            if not spark.catalog.tableExists(full_table_name):
                return True
            return spark.table(full_table_name).isEmpty()
        except AnalysisException:
            return True

    def run_pipeline(
        self, dataframe: DataFrame, args, spark: SparkSession
    ) -> None:
        """Partition-scoped insert-only merge for idempotent event-log writes.

        On the first run (empty target table) the merge is skipped and a direct
        overwrite is used instead, avoiding the expensive full-table scan that
        caused cluster timeouts on historical backfills.
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
    job = CoreListingHistorySparkJob()
    job.run()
