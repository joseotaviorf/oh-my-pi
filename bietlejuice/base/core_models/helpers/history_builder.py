from typing import Dict, List, Optional, Tuple
from functools import reduce

from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from pyspark.sql.window import Window

from bietlejuice.base.core_models.helpers.event_config_resolution import (
    resolve_event_name,
)
from bietlejuice.base.core_models.helpers.surrogate_keys import SurrogateKeysHelper


class HistoryBuilder:
    """Converts transactional CDC rows into narrow, fixed-schema event rows.

    Each tracked column change becomes its own row in the historical table,
    enabling field-level change tracking across any Core Model entity.
    The output schema is identical regardless of the entity being tracked.
    """

    # Each entry needs tracked_col plus either event_name or target_col (see resolve_event_name).
    REQUIRED_EVENT_CONFIG_KEYS = {"tracked_col"}

    @staticmethod
    def build_history_for_columns(
        df: DataFrame,
        entity_name: str,
        id_col: str,
        ts_col: str,
        op_col: str,
        event_configs: List[Dict[str, str]],
        event_type: str = "cdc",
        event_origin: str = "",
    ) -> DataFrame:
        """Convert a transactional DataFrame into narrow event rows.

        For CDC sources, uses LAG-based change detection and sets
        ``payload`` to NULL.  For outbox sources (future), maps directly
        from the source event and preserves the payload content.

        Args:
            df: Pre-loaded transactional DataFrame with CDC columns.
            entity_name: Lowercase entity name (e.g. ``"contract"``).
            id_col: Column holding the entity id in the source table
                (e.g. ``"id"``).
            ts_col: Transaction timestamp column
                (e.g. ``"ts_database_transaction"``).
            op_col: CDC operation column (e.g. ``"op_cdc"``).
            event_configs: List of dicts with ``tracked_col`` and either
                ``event_name`` or ``target_col`` (``ev_{target_col}`` if omitted).
            event_type: ``"cdc"`` or ``"outbox_pattern"``.
            event_origin: Fully qualified source table name
                (e.g. ``"datalake_ebdb_transactional.contrato"``).

        Returns:
            DataFrame with the fixed historical schema:
            ``id_event``, ``id_{entity}``, ``sk_{entity}``,
            ``event_name``, ``event_type``, ``value``, ``payload``,
            ``ts_transaction``, ``event_origin``, ``ts_load``,
            ``year``, ``month``, ``day``.
        """
        HistoryBuilder._validate_event_configs(event_configs)

        tracked_cols = [ec["tracked_col"] for ec in event_configs]
        id_entity_col = f"id_{entity_name}"

        cols_to_select = list({id_col, ts_col, op_col} | set(tracked_cols))
        df_source = df.select(*[F.col(c) for c in cols_to_select])

        spark = df_source.sparkSession
        shuffle_partitions = int(spark.conf.get("spark.sql.shuffle.partitions", "200"))
        df_source = df_source.repartition(shuffle_partitions, F.col(id_col))

        default_values = HistoryBuilder._extract_default_values(event_configs)

        # Cache the narrow, repartitioned DataFrame so the 29-branch union
        # that follows can share a single shuffle + window evaluation.
        # Caching here (not on the raw wide source) keeps the footprint small:
        # only the ~32 relevant columns are materialised into executor memory.
        df_source.cache()
        try:
            df_with_prev = HistoryBuilder._apply_lag_windows(
                df_source, id_col, ts_col, tracked_cols, default_values
            )

            event_dfs = HistoryBuilder._detect_and_pivot(
                df_with_prev,
                event_configs,
                id_col,
                ts_col,
                op_col,
                id_entity_col,
                event_type,
                event_origin,
            )

            result_df = reduce(DataFrame.unionByName, event_dfs)

            result_df = HistoryBuilder._generate_keys(
                result_df, entity_name, id_entity_col
            )

            result_df = HistoryBuilder._add_metadata_columns(result_df)

            return HistoryBuilder._select_output_columns(
                result_df, id_entity_col, entity_name
            )
        finally:
            df_source.unpersist()

    @staticmethod
    def _validate_event_configs(event_configs: List[Dict[str, str]]) -> None:
        if not event_configs:
            raise ValueError("event_configs must not be empty")
        for i, ec in enumerate(event_configs):
            missing = HistoryBuilder.REQUIRED_EVENT_CONFIG_KEYS - set(ec.keys())
            if missing:
                raise ValueError(f"event_configs[{i}] missing required keys: {missing}")
            resolve_event_name(ec, index=i)

    @staticmethod
    def _extract_default_values(
        event_configs: List[Dict[str, str]],
    ) -> Dict[str, Tuple[str, str]]:
        """Extract columns that carry a default_value from event_configs.

        Returns a dict mapping tracked_col → (default_value_str, spark_type_str).
        Only entries that explicitly declare ``default_value`` are included.
        ``target_type`` is used as the Spark cast target; falls back to "string".
        """
        return {
            ec["tracked_col"]: (ec["default_value"], ec.get("target_type", "string"))
            for ec in event_configs
            if "default_value" in ec
        }

    @staticmethod
    def _apply_lag_windows(
        df: DataFrame,
        id_col: str,
        ts_col: str,
        tracked_cols: List[str],
        default_values: Optional[Dict[str, Tuple[str, str]]] = None,
    ) -> DataFrame:
        """Apply coalesce defaults then compute LAG windows for change detection.

        When a column has a ``default_value`` (from ``_extract_default_values``),
        a coalesce is applied **before** the LAG window so that:
        - Change detection operates on the effective (post-transformation) value.
        - Transitions like ``null → false`` (same effective value) are correctly
          suppressed rather than emitting a spurious event.
        - The stored ``value`` in the output row already reflects the default.
        """
        if default_values is None:
            default_values = {}

        for col_name, (default_val, col_type) in default_values.items():
            df = df.withColumn(
                col_name,
                F.coalesce(F.col(col_name), F.lit(default_val).cast(col_type)),
            )

        w = Window.partitionBy(id_col).orderBy(ts_col)
        for col_name in tracked_cols:
            df = df.withColumn(f"_prev_{col_name}", F.lag(F.col(col_name)).over(w))
        return df

    @staticmethod
    def _detect_and_pivot(
        df_with_prev: DataFrame,
        event_configs: List[Dict[str, str]],
        id_col: str,
        ts_col: str,
        op_col: str,
        id_entity_col: str,
        event_type: str,
        event_origin: str,
    ) -> List[DataFrame]:
        """Build one event DataFrame per tracked column, filtered to changed rows."""
        event_dfs = []

        for ec in event_configs:
            tracked_col = ec["tracked_col"]
            event_name = resolve_event_name(ec)
            prev_col = f"_prev_{tracked_col}"

            # Null-safe inequality: handles NULL->value, value->NULL,
            # and NULL==NULL correctly.
            values_differ = (
                ~F.col(tracked_col)
                .cast("string")
                .eqNullSafe(F.col(prev_col).cast("string"))
            )

            changed_expr = (
                (F.col(op_col) == F.lit("c"))
                | (F.col(op_col) == F.lit("d"))
                | ((F.col(op_col) == F.lit("u")) & values_differ)
            )

            event_df = df_with_prev.filter(changed_expr).select(
                F.col(id_col).cast("string").alias(id_entity_col),
                F.lit(event_name).alias("event_name"),
                F.lit(event_type).alias("event_type"),
                F.col(tracked_col).cast("string").alias("value"),
                F.lit(None).cast("string").alias("payload"),
                F.col(ts_col).alias("ts_transaction"),
                F.lit(event_origin).alias("event_origin"),
            )
            event_dfs.append(event_df)

        return event_dfs

    @staticmethod
    def _generate_keys(
        df: DataFrame, entity_name: str, id_entity_col: str
    ) -> DataFrame:
        df = df.withColumn(
            "id_event",
            F.sha2(
                F.concat_ws(
                    "||",
                    F.col(id_entity_col),
                    F.col("event_name"),
                    F.col("ts_transaction").cast("string"),
                ),
                256,
            ),
        )
        df = SurrogateKeysHelper.generate_surrogate_key(
            df, entity_name.upper(), id_column=id_entity_col
        )
        return df.withColumnRenamed("surrogate_key", f"sk_core_{entity_name}")

    @staticmethod
    def _add_metadata_columns(df: DataFrame) -> DataFrame:
        return (
            df.withColumn("ts_load", F.current_timestamp())
            .withColumn("year", F.year(F.col("ts_transaction")))
            .withColumn("month", F.month(F.col("ts_transaction")))
            .withColumn("day", F.dayofmonth(F.col("ts_transaction")))
        )

    @staticmethod
    def _select_output_columns(
        df: DataFrame, id_entity_col: str, entity_name: str
    ) -> DataFrame:
        return df.select(
            "id_event",
            id_entity_col,
            f"sk_core_{entity_name}",
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
