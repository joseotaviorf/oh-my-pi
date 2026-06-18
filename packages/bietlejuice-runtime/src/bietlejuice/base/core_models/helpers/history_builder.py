from functools import reduce
from typing import Dict, List, Optional, Tuple

from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from pyspark.sql.window import Window

from bietlejuice.base.core_models.helpers.event_config_resolution import (
    resolve_event_name,
)
from bietlejuice.base.core_models.helpers.surrogate_keys import SurrogateKeysHelper

# Ordered tie-breaker chain used to canonicalize multiple CDC rows that share the
# same ``(entity_id, ts_database_transaction)``. The first column resolves ties
# first, then the second, and so on. Only columns actually present in the input
# DataFrame are used (see ``_resolve_tie_breaker_columns``), so the same default
# self-adapts across sources with different schemas:
#   - ``version`` / ``updated_at`` (source recency): pick the newest TRUE revision
#     when a source replays multiple historical states at one transaction instant.
#   - ``ts_cdc_transaction`` / ``cdc_binlog_position`` / ``cdc_transaction_id``
#     (ingest recency): universal CDC metadata, present on every transactional
#     table, used as the fallback when source-recency columns are absent.
# No value normalization is applied: different stored values stay different.
DEFAULT_CANONICALIZE_TIE_BREAKERS = [
    "version",
    "updated_at",
    "ts_cdc_transaction",
    "cdc_binlog_position",
    "cdc_transaction_id",
]

# Opt-in precisions for the ``value_precision`` event-config key. A tracked
# timestamp column is truncated to the requested precision *before* change
# detection (and storage), so byte-level rendering differences that do not
# change the business value stop emitting spurious events. The canonical case:
# a CDC snapshot (``op_cdc='r'``) renders ``created_at`` at millisecond
# precision while streaming ``c``/``u`` rows render it at microsecond
# precision; ``value_precision: millisecond`` collapses both to one value so an
# immutable column emits exactly one event.
SUPPORTED_VALUE_PRECISIONS = ("second", "millisecond", "microsecond")


class HistoryBuilder:
    """Converts transactional CDC rows into narrow, fixed-schema event rows.

    Each tracked column change becomes its own row in the historical table,
    enabling field-level change tracking across any Core Model entity.
    The output schema is identical regardless of the entity being tracked.

    CDC operations ``c`` (create), ``d`` (delete), ``u`` (update), and ``r``
    (snapshot/read) are supported. Snapshot reads use the same LAG-based
    change detection as updates; ``ts_transaction`` on ``r`` rows reflects
    the snapshot instant, not the original business event time.
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
        canonicalize_tie_breaker_columns: Optional[List[str]] = None,
    ) -> DataFrame:
        """Convert a transactional DataFrame into narrow event rows.

        For CDC sources, uses LAG-based change detection and sets
        ``payload`` to NULL.  For outbox sources (future), maps directly
        from the source event and preserves the payload content.

        Transactional CDC can emit many rows per
        ``(entity_id, ts_database_transaction)`` (notably on Debezium snapshot
        batches), all of which would collide on the same ``id_event``
        (hashed from id, event_name and ts only). To enforce the documented
        history grain of one event per ``(entity_id, event_name, ts)``, the
        input is canonicalized to a single row per
        ``(entity_id, ts_database_transaction)`` before change detection.

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
                Optional ``value_precision`` (``second`` / ``millisecond`` /
                ``microsecond``) truncates a tracked timestamp column before
                change detection, so snapshot vs streaming-CDC render
                differences on an immutable column stop emitting extra events.
            event_type: ``"cdc"`` or ``"outbox_pattern"``.
            event_origin: Fully qualified source table name
                (e.g. ``"datalake_ebdb_transactional.contrato"``).
            canonicalize_tie_breaker_columns: Ordered tie-breaker chain used to
                pick the surviving row when several rows share the same
                ``(entity_id, ts_database_transaction)``. The first column wins
                ties first, then the second, etc. (all applied ``DESC`` with
                nulls last). Only columns present in ``df`` are used. Defaults to
                ``DEFAULT_CANONICALIZE_TIE_BREAKERS`` (source-recency columns
                first, universal CDC metadata as fallback). Override per-source
                only when a table both lacks ``version``/``updated_at`` and
                replays distinct payloads at one transaction instant that only a
                source-recency column orders correctly. No value normalization is
                applied.

        Returns:
            DataFrame with the fixed historical schema:
            ``id_event``, ``id_{entity}``, ``sk_{entity}``,
            ``event_name``, ``event_type``, ``value``, ``payload``,
            ``ts_transaction``, ``event_origin``, ``ts_load``,
            ``year``, ``month``, ``day``.
        """
        HistoryBuilder._validate_event_configs(event_configs)

        tracked_cols = [ec["tracked_col"] for ec in event_configs]
        json_derived_columns = HistoryBuilder._extract_json_derived_columns(
            event_configs
        )
        raw_tracked_cols = [
            col_name
            for col_name in tracked_cols
            if col_name not in json_derived_columns
        ]
        source_cols = [source_col for source_col, _ in json_derived_columns.values()]
        id_entity_col = f"id_{entity_name}"

        tie_breaker_columns = HistoryBuilder._resolve_tie_breaker_columns(
            df, canonicalize_tie_breaker_columns
        )
        # ``version`` / ``updated_at`` participate in the exact-dedupe key (when
        # present) even if a custom tie-breaker override omits them, so distinct
        # source revisions are never collapsed before canonicalization.
        recency_cols = [c for c in ("version", "updated_at") if c in df.columns]

        cols_to_select = list(
            {id_col, ts_col, op_col}
            | set(raw_tracked_cols)
            | set(source_cols)
            | set(tie_breaker_columns)
            | set(recency_cols)
        )
        df_source = df.select(*[F.col(c) for c in cols_to_select])
        df_source = HistoryBuilder._materialize_json_derived_columns(
            df_source, json_derived_columns
        )
        # Normalize tracked-timestamp precision before any dedupe / change
        # detection so the snapshot (millis) and streaming-CDC (micros) renders
        # of an immutable column compare equal and emit a single event.
        value_precisions = HistoryBuilder._extract_value_precisions(event_configs)
        df_source = HistoryBuilder._normalize_value_precisions(
            df_source, value_precisions
        )

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
            # Step 1: drop byte-identical business rows (e.g. partition-artifact
            # pairs that differ only in year/month/day/hour or CDC metadata).
            df_canonical = HistoryBuilder._dedupe_identical_rows(
                df_source, id_col, ts_col, op_col, tracked_cols
            )
            # Step 2: collapse to one row per (entity_id, ts_database_transaction)
            # using the resolved tie-breaker chain.
            df_canonical = HistoryBuilder._canonicalize_to_one_row_per_timestamp(
                df_canonical, id_col, ts_col, tie_breaker_columns
            )

            # Step 3: LAG with the same tie-breaker ordering so the "previous row"
            # aligns with the surviving canonical row.
            df_with_prev = HistoryBuilder._apply_lag_windows(
                df_canonical,
                id_col,
                ts_col,
                tracked_cols,
                default_values,
                tie_breaker_columns,
            )

            # Step 4: change detection (c / d / u / r) -- unchanged.
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

            # Step 5: safety net -- guarantee a unique id_event per batch even if
            # a future source quirk slips through the canonicalization above.
            result_df = result_df.dropDuplicates(["id_event"])

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
            has_json_path = "json_path" in ec
            has_source_col = "source_col" in ec
            if has_json_path != has_source_col:
                raise ValueError(
                    f"event_configs[{i}] must declare both 'source_col' and "
                    f"'json_path' when using JSON-derived tracking"
                )
            precision = ec.get("value_precision")
            if precision is not None and precision not in SUPPORTED_VALUE_PRECISIONS:
                raise ValueError(
                    f"event_configs[{i}] has unsupported value_precision "
                    f"'{precision}'; expected one of {SUPPORTED_VALUE_PRECISIONS}"
                )
            resolve_event_name(ec, index=i)

    @staticmethod
    def _extract_json_derived_columns(
        event_configs: List[Dict[str, str]],
    ) -> Dict[str, Tuple[str, str]]:
        """Extract JSON-derived tracked columns declared in event_configs.

        Returns a dict mapping tracked_col → (source_col, json_path).
        Only entries that explicitly declare both ``source_col`` and ``json_path``
        are included.
        """
        return {
            ec["tracked_col"]: (ec["source_col"], ec["json_path"])
            for ec in event_configs
            if "source_col" in ec and "json_path" in ec
        }

    @staticmethod
    def _materialize_json_derived_columns(
        df: DataFrame,
        json_derived_columns: Dict[str, Tuple[str, str]],
    ) -> DataFrame:
        """Materialize tracked columns derived from JSON payload fields."""
        for tracked_col, (source_col, json_path) in json_derived_columns.items():
            df = df.withColumn(
                tracked_col, F.get_json_object(F.col(source_col), json_path)
            )
        return df

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
    def _extract_value_precisions(
        event_configs: List[Dict[str, str]],
    ) -> Dict[str, str]:
        """Extract columns that declare a ``value_precision`` from event_configs.

        Returns a dict mapping tracked_col → precision unit (one of
        ``SUPPORTED_VALUE_PRECISIONS``). Only entries that explicitly declare
        ``value_precision`` are included.
        """
        return {
            ec["tracked_col"]: ec["value_precision"]
            for ec in event_configs
            if "value_precision" in ec
        }

    @staticmethod
    def _normalize_value_precisions(
        df: DataFrame, value_precisions: Dict[str, str]
    ) -> DataFrame:
        """Truncate tracked timestamp columns to their declared precision.

        Applied before dedupe / LAG / change detection so the truncated value
        drives both the comparison and the stored ``value``. A no-op when
        ``value_precisions`` is empty.
        """
        for col_name, precision in value_precisions.items():
            df = df.withColumn(
                col_name, HistoryBuilder._truncate_timestamp(col_name, precision)
            )
        return df

    @staticmethod
    def _truncate_timestamp(col_name: str, precision: str):
        """Return a Column truncating ``col_name`` (cast to timestamp) to precision.

        Uses Spark SQL functions available since Spark 3.1 (``date_trunc``,
        ``unix_micros``, ``timestamp_micros``, ``pmod``) so the rewrite runs
        identically on Databricks DBR 16.4 and EMR Spark 3.5.
        """
        ts = f"CAST(`{col_name}` AS TIMESTAMP)"
        if precision == "second":
            return F.expr(f"date_trunc('SECOND', {ts})")
        if precision == "millisecond":
            return F.expr(
                f"timestamp_micros(unix_micros({ts}) - pmod(unix_micros({ts}), 1000))"
            )
        # microsecond: cast-only, canonicalizes representation without loss.
        return F.expr(ts)

    @staticmethod
    def _resolve_tie_breaker_columns(
        df: DataFrame, requested: Optional[List[str]]
    ) -> List[str]:
        """Filter the requested (or default) tie-breaker list to present columns.

        Preserves the requested order and keeps only columns that actually exist
        in ``df`` (case-sensitive match against the source column names), so the
        same default chain self-adapts across sources with different schemas.
        """
        columns = (
            requested if requested is not None else DEFAULT_CANONICALIZE_TIE_BREAKERS
        )
        return [col_name for col_name in columns if col_name in df.columns]

    @staticmethod
    def _dedupe_identical_rows(
        df: DataFrame,
        id_col: str,
        ts_col: str,
        op_col: str,
        tracked_cols: List[str],
    ) -> DataFrame:
        """Drop byte-identical business rows (Step 1 of canonicalization).

        Collapses rows that share the same identity, transaction instant,
        operation, tracked values and source-recency columns
        (``version`` / ``updated_at`` when present). CDC metadata and partition
        columns are intentionally excluded from the key so partition-artifact
        pairs (same payload, different ``year`` / ``month`` / ``day`` / ``hour``
        or binlog position) collapse to one row.
        """
        recency_cols = [c for c in ("version", "updated_at") if c in df.columns]
        dedupe_key = list(
            dict.fromkeys([id_col, ts_col, op_col, *tracked_cols, *recency_cols])
        )
        return df.dropDuplicates(dedupe_key)

    @staticmethod
    def _canonicalize_to_one_row_per_timestamp(
        df: DataFrame,
        id_col: str,
        ts_col: str,
        tie_breaker_columns: List[str],
    ) -> DataFrame:
        """Keep one row per ``(entity_id, ts_database_transaction)`` (Step 2).

        Ranks rows within each ``(id_col, ts_col)`` group by the resolved
        tie-breaker chain (``DESC``, nulls last) and keeps the top row. When no
        tie-breaker columns are present the surviving row is non-deterministic,
        but the grain (one row per id+ts) is still enforced.
        """
        if tie_breaker_columns:
            order_by = [
                F.col(col_name).desc_nulls_last() for col_name in tie_breaker_columns
            ]
        else:
            order_by = [F.col(ts_col)]
        w = Window.partitionBy(id_col, ts_col).orderBy(*order_by)
        return (
            df.withColumn("_rn", F.row_number().over(w))
            .filter(F.col("_rn") == 1)
            .drop("_rn")
        )

    @staticmethod
    def _apply_lag_windows(
        df: DataFrame,
        id_col: str,
        ts_col: str,
        tracked_cols: List[str],
        default_values: Optional[Dict[str, Tuple[str, str]]] = None,
        tie_breaker_columns: Optional[List[str]] = None,
    ) -> DataFrame:
        """Apply coalesce defaults then compute LAG windows for change detection.

        When a column has a ``default_value`` (from ``_extract_default_values``),
        a coalesce is applied **before** the LAG window so that:
        - Change detection operates on the effective (post-transformation) value.
        - Transitions like ``null → false`` (same effective value) are correctly
          suppressed rather than emitting a spurious event.
        - The stored ``value`` in the output row already reflects the default.

        The LAG window orders by ``ts_col`` then the same tie-breaker columns used
        for canonicalization, so the "previous row" is deterministic and aligns
        with the surviving canonical row at each timestamp.
        """
        if default_values is None:
            default_values = {}
        if tie_breaker_columns is None:
            tie_breaker_columns = []

        for col_name, (default_val, col_type) in default_values.items():
            df = df.withColumn(
                col_name,
                F.coalesce(F.col(col_name), F.lit(default_val).cast(col_type)),
            )

        order_by = [F.col(ts_col)] + [
            F.col(col_name).desc_nulls_last() for col_name in tie_breaker_columns
        ]
        w = Window.partitionBy(id_col).orderBy(*order_by)
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
        """Build one event DataFrame per tracked column, filtered to changed rows.

        Inserts (``c``) and deletes (``d``) always emit. Updates (``u``) and
        snapshot reads (``r``) emit only when the tracked value changed vs the
        prior row (null-safe). For ``r``, ``ts_transaction`` is the snapshot
        instant, not the original event time.
        """
        event_dfs = []

        for ec in event_configs:
            tracked_col = ec["tracked_col"]
            event_name = resolve_event_name(ec)
            prev_col = f"_prev_{tracked_col}"

            # Null-safe inequality: handles NULL->value, value->NULL,
            # and NULL==NULL correctly.
            values_differ = ~F.col(tracked_col).cast("string").eqNullSafe(
                F.col(prev_col).cast("string")
            )

            changed_expr = (
                (F.col(op_col) == F.lit("c"))
                | (F.col(op_col) == F.lit("d"))
                | ((F.col(op_col) == F.lit("u")) & values_differ)
                | ((F.col(op_col) == F.lit("r")) & values_differ)
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
