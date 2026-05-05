import ast

from pyspark.sql import SparkSession, DataFrame
from pyspark.sql import functions as F
from pyspark.sql.window import Window
from pyspark.sql.utils import AnalysisException

from bietlejuice.base.spark.base_core_model_spark_job import BaseCoreModelSparkJob
from bietlejuice.base.core_models.helpers.historical_helper import HistoricalHelper
from bietlejuice.base.core_models.helpers.history_builder import HistoryBuilder
from bietlejuice.base.core_models.helpers.surrogate_keys import SurrogateKeysHelper
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.pipeline.dataframe_delta_table_loader_pipeline import (
    DataFrameDeltaTableLoaderPipeline,
)

JOB_NAME = "house_history"

_HLR_DELETED_SENTINEL = "__DELETED__"


class CoreHouseHistorySparkJob(BaseCoreModelSparkJob):
    """Builds the narrow event-log history table for the house entity.

    Reads CDC data from ``datalake_ebdb_transactional.imovel``, detects
    field-level changes via LAG windows, and writes each changed field into
    ``core_house.house_history``.

    For ``id_owner`` and ``uuid_owner``, replicates the exact ``core_house``
    logic: ``id_owner = coalesce(hlr.relatedId, imovel.usuario_id)`` where
    HLR is filtered to ``relatedAs=PROPERTY_OWNER`` and
    ``sourceType=MAIN_USER`` (most recent record). ``uuid_owner`` is resolved
    from ``usuario.personuuid`` via ``id_owner``.

    Owner changes are detected from a combined timeline of house CDC +
    HLR CDC events, so that both ``usuario_id`` mutations and
    ``ImovelListingRelation`` mutations produce ``ev_id_owner`` /
    ``ev_uuid_owner`` events.

    ``id_user_registrant`` is pre-processed as
    ``coalesce(originalUsuarioQueCadastrou_id, usuarioQueCadastrou_id)``
    before change detection, matching ``core_house``.

    On the first run (empty target) the merge is skipped for a direct
    overwrite, avoiding full-table scans on historical backfills.
    """

    def __init__(self):
        super().__init__(JOB_NAME)

    # Pre-processing helpers
    def _align_registrant_column(self, df: DataFrame) -> DataFrame:
        """Replicate core_house coalesce for id_user_registrant."""
        return df.withColumn(
            "id_user_registrant",
            F.coalesce(
                F.col("originalUsuarioQueCadastrou_id"),
                F.col("usuarioQueCadastrou_id"),
            ),
        )

    # Owner resolution from combined house + HLR timeline
    def _build_owner_events(
        self,
        spark: SparkSession,
        house_df: DataFrame,
        args,
    ) -> DataFrame:
        """Build ``ev_id_owner`` and ``ev_uuid_owner`` narrow events.

        Creates a unified timeline per house from both house CDC and HLR CDC
        events,     carries forward the HLR owner and ``usuario_id`` state via
    ``last(ignorenulls)`` window, then applies LAG change-detection.
        """
        house_table = self.get_config("HOUSE_TRANSACTIONAL_TABLE")
        hlr_table = self.get_config("HLR_TRANSACTIONAL_TABLE")
        user_table = self.get_config("USER_TRANSACTIONAL_TABLE")

        house_ids_in_range = house_df.select(
            F.col("id").cast("string").alias("house_id")
        ).distinct()

        hlr_all = spark.read.table(hlr_table)
        hlr_owners_all = hlr_all.filter(
            (F.col("relatedAs") == "PROPERTY_OWNER")
            & (F.col("sourceType") == "MAIN_USER")
        )

        hlr_in_range = hlr_owners_all
        if self._has_date_range(args):
            hlr_in_range = hlr_owners_all.filter(
                (F.col("ts_database_transaction").cast("date")
                 >= F.lit(args.load_start_date).cast("date"))
                & (F.col("ts_database_transaction").cast("date")
                   <= F.lit(args.load_end_date).cast("date"))
            )

        hlr_house_ids = hlr_in_range.select(
            F.col("imovelId").cast("string").alias("house_id")
        ).distinct()

        all_owner_house_ids = house_ids_in_range.union(hlr_house_ids).distinct()

        # -- House timeline entries --
        house_timeline = house_df.select(
            F.col("id").cast("string").alias("house_id"),
            F.col("ts_database_transaction").alias("event_ts"),
            F.col("usuario_id").cast("string").alias("_usuario_id"),
            F.col("op_cdc"),
            F.lit(None).cast("string").alias("_hlr_state"),
        )

        # -- HLR timeline entries (full history for carry-forward) --
        hlr_for_houses = hlr_owners_all.join(
            F.broadcast(all_owner_house_ids),
            hlr_owners_all["imovelId"].cast("string")
            == all_owner_house_ids["house_id"],
            "inner",
        ).drop(all_owner_house_ids["house_id"])

        hlr_timeline = hlr_for_houses.select(
            F.col("imovelId").cast("string").alias("house_id"),
            F.col("ts_database_transaction").alias("event_ts"),
            F.lit(None).cast("string").alias("_usuario_id"),
            F.col("op_cdc"),
            F.when(
                F.col("op_cdc").isin("c", "u", "r"),
                F.col("relatedId").cast("string"),
            )
            .when(
                F.col("op_cdc") == "d",
                F.lit(_HLR_DELETED_SENTINEL),
            )
            .alias("_hlr_state"),
        )

        combined = house_timeline.unionByName(hlr_timeline)

        w = Window.partitionBy("house_id").orderBy("event_ts")

        combined = (
            combined
            .withColumn(
                "_carried_hlr",
                F.last("_hlr_state", ignorenulls=True).over(w),
            )
            .withColumn(
                "_carried_usuario",
                F.last("_usuario_id", ignorenulls=True).over(w),
            )
        )

        # -- As-of join: resolve user existence at the time of each event --
        user_df = spark.read.table(user_table).select(
            F.col("id").cast("string").alias("_uid"),
            F.col("personuuid").alias("_puuid"),
            F.col("ts_database_transaction").alias("_user_ts"),
        )

        # HLR path: validate _carried_hlr existed as usuario at event_ts
        hlr_user_join = combined.join(
            user_df.select(
                F.col("_uid").alias("_hlr_uid"),
                F.col("_user_ts").alias("_hlr_user_ts"),
            ),
            (F.col("_carried_hlr") == F.col("_hlr_uid"))
            & (F.col("_hlr_user_ts") <= F.col("event_ts")),
            "left",
        )

        hlr_asof_w = Window.partitionBy(
            "house_id", "event_ts"
        ).orderBy(F.col("_hlr_user_ts").desc())

        combined = (
            hlr_user_join
            .withColumn("_hlr_rn", F.row_number().over(hlr_asof_w))
            .filter(
                F.col("_hlr_rn").isNull() | (F.col("_hlr_rn") == 1)
            )
            .drop("_hlr_rn", "_hlr_user_ts")
        )

        combined = combined.withColumn(
            "_id_owner",
            F.coalesce(F.col("_hlr_uid"), F.col("_carried_usuario")),
        ).withColumn(
            "_id_owner_origin",
            F.when(F.col("_hlr_uid").isNotNull(), F.lit(hlr_table))
            .otherwise(F.lit(house_table)),
        )

        # Resolve uuid_owner from _id_owner via as-of join
        owner_user_join = combined.join(
            user_df.select(
                F.col("_uid").alias("_owner_uid"),
                F.col("_puuid").alias("_uuid_person"),
                F.col("_user_ts").alias("_owner_user_ts"),
            ),
            (F.col("_id_owner") == F.col("_owner_uid"))
            & (F.col("_owner_user_ts") <= F.col("event_ts")),
            "left",
        )

        owner_asof_w = Window.partitionBy(
            "house_id", "event_ts"
        ).orderBy(F.col("_owner_user_ts").desc())

        combined = (
            owner_user_join
            .withColumn("_owner_rn", F.row_number().over(owner_asof_w))
            .filter(
                F.col("_owner_rn").isNull() | (F.col("_owner_rn") == 1)
            )
            .drop("_owner_rn", "_owner_user_ts", "_owner_uid")
        )

        combined = combined.withColumn(
            "_prev_id_owner", F.lag("_id_owner").over(w)
        )

        owner_changed = combined.filter(
            F.col("_prev_id_owner").isNull()
            | (~F.col("_id_owner").eqNullSafe(F.col("_prev_id_owner")))
        )

        if self._has_date_range(args):
            owner_changed = owner_changed.filter(
                (F.col("event_ts").cast("date")
                 >= F.lit(args.load_start_date).cast("date"))
                & (F.col("event_ts").cast("date")
                   <= F.lit(args.load_end_date).cast("date"))
            )

        ev_id_owner = self._format_owner_event(
            owner_changed, "ev_id_owner", "_id_owner",
            "_id_owner_origin", is_column=True,
        )
        ev_uuid_owner = self._format_owner_event(
            owner_changed, "ev_uuid_owner", "_uuid_person",
            user_table,
        )

        return ev_id_owner.unionByName(ev_uuid_owner)

    def _format_owner_event(
        self,
        df: DataFrame,
        event_name: str,
        value_col: str,
        origin_col_or_literal: str,
        is_column: bool = False,
    ) -> DataFrame:
        """Shape an owner-change DataFrame into the standard 13-col schema."""
        origin_expr = (
            F.col(origin_col_or_literal)
            if is_column
            else F.lit(origin_col_or_literal)
        )
        events = df.select(
            F.col("house_id").alias("id_house"),
            F.lit(event_name).alias("event_name"),
            F.lit("cdc").alias("event_type"),
            F.col(value_col).cast("string").alias("value"),
            F.lit(None).cast("string").alias("payload"),
            F.col("event_ts").alias("ts_transaction"),
            origin_expr.alias("event_origin"),
        )

        events = events.withColumn(
            "id_event",
            F.sha2(
                F.concat_ws(
                    "||",
                    F.col("id_house"),
                    F.col("event_name"),
                    F.col("ts_transaction").cast("string"),
                ),
                256,
            ),
        )
        events = SurrogateKeysHelper.generate_surrogate_key(
            events, "HOUSE", id_column="id_house"
        ).withColumnRenamed("surrogate_key", "sk_core_house")

        return (
            events
            .withColumn("ts_load", F.current_timestamp())
            .withColumn("year", F.year(F.col("ts_transaction")))
            .withColumn("month", F.month(F.col("ts_transaction")))
            .withColumn("day", F.dayofmonth(F.col("ts_transaction")))
            .select(
                "id_event", "id_house", "sk_core_house",
                "event_name", "event_type", "value", "payload",
                "ts_transaction", "event_origin", "ts_load",
                "year", "month", "day",
            )
        )

    @staticmethod
    def _has_date_range(args) -> bool:
        return (
            args.load_start_date is not None
            and args.load_start_date != ""
            and args.load_end_date is not None
            and args.load_end_date != ""
        )


    def create_core_model(self, spark: SparkSession, args) -> DataFrame:
        """Build the house history DataFrame."""
        house_table = self.get_config("HOUSE_TRANSACTIONAL_TABLE")
        event_configs = self.get_config("event_configs")

        self.logger.info(
            f"m=create_core_model, "
            f"msg=Building house history from {house_table}, "
            f"date_range={args.load_start_date}..{args.load_end_date}"
        )

        house_df = HistoricalHelper.load_transactional_data(
            spark, house_table, args
        )
        house_df = self._align_registrant_column(house_df)

        field_events_df = HistoryBuilder.build_history_for_columns(
            house_df,
            entity_name="house",
            id_col="id",
            ts_col="ts_database_transaction",
            op_col="op_cdc",
            event_configs=event_configs,
            event_type="cdc",
            event_origin=house_table,
        )

        owner_events_df = self._build_owner_events(spark, house_df, args)

        return field_events_df.unionByName(owner_events_df)


    def _is_target_table_empty(
        self, spark: SparkSession, full_table_name: str
    ) -> bool:
        try:
            if not spark.catalog.tableExists(full_table_name):
                return True
            return spark.table(full_table_name).isEmpty()
        except AnalysisException:
            return True

    def run_pipeline(self, dataframe: DataFrame, args, spark: SparkSession) -> None:
        """Partition-scoped insert-only merge for idempotent event-log writes."""
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
    job = CoreHouseHistorySparkJob()
    job.run()
