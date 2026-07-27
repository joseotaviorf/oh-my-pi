from collections import defaultdict
from functools import reduce
from typing import Dict, List, Optional, Tuple

from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from pyspark.sql.window import Window

from bietlejuice.base.core_models.helpers.event_config_resolution import (
    resolve_event_name,
)
from bietlejuice.base.core_models.helpers.historical_helper import HistoricalHelper
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

    # Transient CDC op column carried through the enrichment pipeline and
    # dropped before the final select.
    _CDC_OP_COL = "_cdc_op"

    # Internal source name used when the singular aud_df/aud_config API is
    # used; event_configs never reference it explicitly.
    _AUD_DEFAULT_SOURCE = "__default__"

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
        aud_df: Optional[DataFrame] = None,
        aud_config: Optional[Dict] = None,
        aud_dfs: Optional[Dict[str, DataFrame]] = None,
        aud_configs: Optional[List[Dict]] = None,
    ) -> DataFrame:
        """Convert a transactional DataFrame into narrow event rows.

        For CDC sources, uses LAG-based change detection. When AUD data is
        provided (either the singular ``aud_df``/``aud_config`` pair or the
        plural ``aud_dfs``/``aud_configs`` pair) with ``enabled: true``,
        each emitted event row is enriched with AUD revision metadata in the
        ``payload`` column (JSON string). Otherwise ``payload`` is NULL.

        The payload always includes ``op_cdc`` and ``rev_type`` so consumers
        can detect delete events without a schema change to the history table.

        For ``op_cdc='r'`` (snapshot reads), ``payload`` stays NULL regardless
        of AUD config: snapshot rows are not primary delta events.

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
                ``event_name`` or ``target_col`` (``ev_{target_col}`` if
                omitted).  Include ``aud_mod_col`` per entry to enable AUD
                enrichment for that column. When more than one AUD source is
                configured (via ``aud_configs``), each entry with an
                ``aud_mod_col`` must also declare ``aud_source: <name>`` to
                pick which AUD table enriches it; with exactly one source the
                key is optional and defaults to that sole source.
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
            aud_df: Pre-loaded AUD DataFrame returned by
                ``HistoricalHelper.load_aud_revision_data()``.  When None,
                ``payload`` is always NULL. Mutually exclusive with
                ``aud_dfs``/``aud_configs``.
            aud_config: Dict matching the ``aud_config`` YAML block. Required
                keys: ``aud_id_col``, ``aud_table``. Must include
                ``enabled: true`` to activate enrichment. All other keys
                (``revision_pk_col``, ``revision_type_col``, ...) fall back to
                the shared transactional Envers defaults in
                ``HistoricalHelper.DEFAULT_TRANSACTIONAL_ENVERS_CONFIG`` unless
                explicitly overridden -- see
                ``HistoricalHelper.resolve_aud_config``.
            aud_dfs: Dict mapping AUD source name to its pre-loaded DataFrame,
                as returned by ``HistoricalHelper.load_aud_revision_datasets``.
                Mutually exclusive with the singular ``aud_df``/``aud_config``.
            aud_configs: List of ``aud_config`` dicts (same shape as
                ``aud_config``), each with a unique ``name`` matching a key in
                ``aud_dfs``. Each config is resolved independently via
                ``HistoricalHelper.resolve_aud_config``, so sources with
                different conventions (e.g. ``rEVTYPE`` vs ``REVTYPE``) can
                coexist.

        Returns:
            DataFrame with the fixed historical schema:
            ``id_event``, ``id_{entity}``, ``sk_{entity}``,
            ``event_name``, ``event_type``, ``value``, ``payload``,
            ``ts_transaction``, ``event_origin``, ``ts_load``,
            ``year``, ``month``, ``day``.
        """
        HistoryBuilder._validate_event_configs(event_configs)

        aud_sources = HistoryBuilder._normalize_aud_sources(
            aud_df, aud_config, aud_dfs, aud_configs
        )
        aud_enabled = bool(aud_sources)
        if aud_configs:
            declared_aud_names = [
                str(cfg["name"]).strip() for cfg in aud_configs if cfg.get("name")
            ]
        else:
            declared_aud_names = [HistoryBuilder._AUD_DEFAULT_SOURCE]
        aud_event_routing = (
            HistoryBuilder._resolve_event_aud_routing(
                event_configs, aud_sources, declared_aud_names
            )
            if aud_enabled
            else {}
        )

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
        shuffle_partitions = int(
            spark.conf.get("spark.sql.shuffle.partitions", "200") or "200"
        )
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
                carry_cdc_op=aud_enabled,
            )

            result_df = reduce(DataFrame.unionByName, event_dfs)

            if aud_enabled:
                result_df = HistoryBuilder._enrich_payload_from_aud(
                    result_df,
                    aud_sources,
                    id_entity_col,
                    aud_event_routing,
                )

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
    def _normalize_aud_sources(
        aud_df: Optional[DataFrame],
        aud_config: Optional[Dict],
        aud_dfs: Optional[Dict[str, DataFrame]],
        aud_configs: Optional[List[Dict]],
    ) -> Dict[str, Tuple[DataFrame, Dict]]:
        """Normalize the singular/plural AUD params into one canonical shape.

        Returns a dict mapping AUD source name to
        ``(aud_df, resolved_aud_config)``. The singular pair maps to a single
        entry under the internal ``_AUD_DEFAULT_SOURCE`` key. Disabled
        configs and sources without a loaded DataFrame are excluded, so an
        empty dict means "no enrichment".

        Raises:
            ValueError: If both the singular (``aud_df``/``aud_config``) and
                plural (``aud_dfs``/``aud_configs``) forms are supplied, if a
                plural entry is missing ``name``, or if an ``aud_dfs`` key has
                no matching ``aud_configs`` entry.
        """
        singular_given = aud_df is not None or aud_config is not None
        plural_given = aud_dfs is not None or aud_configs is not None
        if singular_given and plural_given:
            raise ValueError(
                "Pass either the singular aud_df/aud_config or the plural "
                "aud_dfs/aud_configs, not both"
            )

        aud_sources: Dict[str, Tuple[DataFrame, Dict]] = {}

        if singular_given:
            if (
                aud_df is not None
                and aud_config is not None
                and aud_config.get("enabled", False)
            ):
                aud_sources[HistoryBuilder._AUD_DEFAULT_SOURCE] = (
                    aud_df,
                    HistoricalHelper.resolve_aud_config(aud_config),
                )
            return aud_sources

        if not aud_dfs or not aud_configs:
            return aud_sources

        configs_by_name: Dict[str, Dict] = {}
        for i, cfg in enumerate(aud_configs):
            name = cfg.get("name")
            if name is None or str(name).strip() == "":
                raise ValueError(f"aud_configs[{i}] must include a non-empty 'name'")
            configs_by_name[str(name).strip()] = cfg

        for name, source_df in aud_dfs.items():
            cfg = configs_by_name.get(name)
            if cfg is None:
                raise ValueError(
                    f"aud_dfs key {name!r} has no matching aud_configs entry; "
                    f"configured names: {sorted(configs_by_name)}"
                )
            if source_df is not None and cfg.get("enabled", False):
                aud_sources[name] = (
                    source_df,
                    HistoricalHelper.resolve_aud_config(cfg),
                )

        return aud_sources

    @staticmethod
    def _resolve_event_aud_routing(
        event_configs: List[Dict[str, str]],
        aud_sources: Dict[str, Tuple[DataFrame, Dict]],
        declared_source_names: List[str],
    ) -> Dict[str, Tuple[str, str]]:
        """Map each enrichable event_name to its ``(aud_source_name, mod_col)``.

        Entries without ``aud_mod_col`` are skipped (never enriched). With a
        single *declared* source, ``aud_source`` is optional and defaults to
        it; with multiple declared sources it becomes mandatory so routing is
        always explicit. An entry routed to a declared-but-disabled (or
        unloaded) source is silently skipped — the source can be toggled off
        without touching every event_config — while a name that was never
        declared raises.

        Raises:
            ValueError: If an entry references an undeclared ``aud_source``,
                or omits it while more than one AUD source is declared.
        """
        sole_source = (
            declared_source_names[0] if len(declared_source_names) == 1 else None
        )
        singular_api = declared_source_names == [HistoryBuilder._AUD_DEFAULT_SOURCE]

        routing: Dict[str, Tuple[str, str]] = {}
        for i, ec in enumerate(event_configs):
            if "aud_mod_col" not in ec:
                continue
            aud_source = ec.get("aud_source")
            if aud_source is None:
                if sole_source is None:
                    raise ValueError(
                        f"event_configs[{i}] declares aud_mod_col but no "
                        f"aud_source; aud_source is required when multiple "
                        f"AUD sources are configured "
                        f"({sorted(declared_source_names)})"
                    )
                aud_source = sole_source
            elif aud_source not in declared_source_names:
                if singular_api:
                    raise ValueError(
                        f"event_configs[{i}] declares aud_source "
                        f"{aud_source!r}, but the singular aud_df/aud_config "
                        f"API was used; pass aud_dfs/aud_configs to use named "
                        f"AUD sources"
                    )
                raise ValueError(
                    f"event_configs[{i}] references unknown aud_source "
                    f"{aud_source!r}; configured sources: "
                    f"{sorted(declared_source_names)}"
                )
            if aud_source not in aud_sources:
                # Declared but disabled / not loaded: leave the event
                # un-enriched instead of failing the whole job.
                continue
            routing[resolve_event_name(ec)] = (aud_source, ec["aud_mod_col"])
        return routing

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
            order_by = [F.desc_nulls_last(col_name) for col_name in tie_breaker_columns]
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
            F.desc_nulls_last(col_name) for col_name in tie_breaker_columns
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
        carry_cdc_op: bool = False,
    ) -> List[DataFrame]:
        """Build one event DataFrame per tracked column, filtered to changed rows.

        Inserts (``c``) and deletes (``d``) always emit. Updates (``u``) and
        snapshot reads (``r``) emit only when the tracked value changed vs the
        prior row (null-safe). For ``r``, ``ts_transaction`` is the snapshot
        instant, not the original event time.

        When ``carry_cdc_op`` is True a transient ``_cdc_op`` column carrying
        the original ``op_cdc`` value is included in the output.  This is used
        by the AUD enrichment path and dropped before the final select.
        """
        event_dfs = []

        for ec in event_configs:
            tracked_col = ec["tracked_col"]
            event_name = resolve_event_name(ec)
            prev_col = f"_prev_{tracked_col}"

            # Null-safe inequality: handles NULL->value, value->NULL,
            # and NULL==NULL correctly.
            values_differ = ~F.equal_null(
                F.col(tracked_col).cast("string"),
                F.col(prev_col).cast("string"),
            )

            changed_expr = (
                (F.col(op_col) == F.lit("c"))
                | (F.col(op_col) == F.lit("d"))
                | ((F.col(op_col) == F.lit("u")) & values_differ)
                | ((F.col(op_col) == F.lit("r")) & values_differ)
            )

            select_exprs = [
                F.col(id_col).cast("string").alias(id_entity_col),
                F.lit(event_name).alias("event_name"),
                F.lit(event_type).alias("event_type"),
                F.col(tracked_col).cast("string").alias("value"),
                F.lit(None).cast("string").alias("payload"),
                F.col(ts_col).alias("ts_transaction"),
                F.lit(event_origin).alias("event_origin"),
            ]

            if carry_cdc_op:
                select_exprs.append(F.col(op_col).alias(HistoryBuilder._CDC_OP_COL))

            event_df = df_with_prev.filter(changed_expr).select(*select_exprs)
            event_dfs.append(event_df)

        return event_dfs

    @staticmethod
    def _enrich_payload_from_aud(
        events_df: DataFrame,
        aud_sources: Dict[str, Tuple[DataFrame, Dict]],
        id_entity_col: str,
        event_routing: Dict[str, Tuple[str, str]],
    ) -> DataFrame:
        """Join emitted event rows with AUD revision data and build the payload JSON.

        Supports multiple named AUD sources: ``aud_sources`` maps source name
        to ``(aud_df, resolved_aud_config)`` and ``event_routing`` maps each
        enrichable event_name to its ``(aud_source_name, mod_col)`` (see
        ``_resolve_event_aud_routing``). Each source is projected once with
        its own resolved config, so per-source conventions (``aud_id_col``,
        ``revision_type_col`` casing, ...) are honored independently.

        Join strategy (validated on H1-2025 production data):
        1. Exact match on ``(id_entity, ts_transaction)`` — both tables derive this
           timestamp from the same DB transaction via Debezium; no fuzzy window needed.
        2. ``mod_{aud_mod_col} = true`` discriminator (from event_configs) resolves
           99.96 % of duplicate-timestamp cases. Skipped for ``op_cdc='c'`` (inserts)
           because Hibernate Envers never sets mod flags on insert revisions.
        3. ``MAX(rev)`` tiebreaker handles the remaining 0.04 % of ambiguous pairs.
        4. LEFT JOIN with ``user_revision_entity`` is pre-joined inside each
           ``aud_df`` (done by ``HistoricalHelper.load_aud_revision_data``).
        5. ``op_cdc='r'`` (snapshot read) rows are kept but ``payload`` stays NULL.
        6. Delete events (``op_cdc='d'``) with no AUD match still receive a minimal
           payload containing ``op_cdc='d'`` so consumers can identify deletions.

        Payload JSON uses ``to_json(struct(...))`` and ``create_map`` for
        ``aud_values`` — standard Spark SQL functions, EMR Spark 3.5 compatible.
        """
        cdc_op_col = HistoryBuilder._CDC_OP_COL

        enrichable_event_names = set(event_routing.keys())

        # Rows excluded from enrichment: snapshot reads + events with no mod mapping.
        # For delete events in this bucket the metadata promises a minimal payload
        # so consumers can detect deletions via JSON_EXTRACT(payload, '$.op_cdc').
        non_enrichable_df = events_df.filter(
            ~F.col("event_name").isin(enrichable_event_names)
            | (F.col(cdc_op_col) == F.lit("r"))
        )
        _ne_aud_values = F.create_map(
            F.lower(F.regexp_replace(F.col("event_name"), "^ev_", "")),
            F.col("value"),
        )
        _ne_delete_payload = F.to_json(
            F.struct(
                F.lit(1).alias("payload_version"),
                F.col(cdc_op_col).alias("op_cdc"),
                F.lit(None).cast("long").alias("rev"),
                F.lit(None).cast("int").alias("rev_type"),
                F.lit(None).cast("string").alias("ts_revision"),
                F.lit(None).cast("string").alias("revision_reason"),
                F.lit(None).cast("long").alias("aud_user_id"),
                _ne_aud_values.alias("aud_values"),
            )
        )
        non_enrichable_df = non_enrichable_df.withColumn(
            "payload",
            F.when(F.col(cdc_op_col) == F.lit("d"), _ne_delete_payload).otherwise(
                F.col("payload")
            ),
        )

        enrichable_df = events_df.filter(
            F.col("event_name").isin(enrichable_event_names)
            & (F.col(cdc_op_col) != F.lit("r"))
        )

        # Group event_names by (aud_source, mod_col) so we build one AUD slice
        # per group, each scoped to its own source's DataFrame and config.
        group_to_event_names: Dict[Tuple[str, str], List[str]] = defaultdict(list)
        for ev_name, (source_name, mod_col) in event_routing.items():
            group_to_event_names[(source_name, mod_col)].append(ev_name)

        needed_mod_cols_by_source: Dict[str, List[str]] = defaultdict(list)
        for source_name, mod_col in group_to_event_names:
            if mod_col not in needed_mod_cols_by_source[source_name]:
                needed_mod_cols_by_source[source_name].append(mod_col)

        # Project each referenced AUD source once — rename to the shared
        # ``_aud_*`` aliases (avoiding join ambiguity with events_df) using
        # that source's resolved config, so per-source column conventions
        # (e.g. ``rEVTYPE`` vs ``REVTYPE``) are each read correctly.
        aud_projections: Dict[str, Tuple[DataFrame, List[str]]] = {}
        for source_name, needed_mod_cols in needed_mod_cols_by_source.items():
            source_aud_df, resolved_aud_config = aud_sources[source_name]
            aud_col_set = set(source_aud_df.columns)

            aud_id_col = resolved_aud_config["aud_id_col"]
            revision_pk_col = resolved_aud_config["revision_pk_col"]
            revision_type_col = resolved_aud_config["revision_type_col"]

            base_aud_select = [
                F.col(aud_id_col).cast("string").alias("_aud_id"),
                F.col("ts_database_transaction").cast("timestamp").alias("_aud_ts"),
                F.col(revision_pk_col).alias("_aud_rev"),
                F.col(revision_type_col).alias("_aud_rev_type"),
            ]
            optional_aud_cols = []
            for col_name, alias in [
                ("ts_cdc_transaction", "_aud_ts_cdc"),
                ("ts_revision", "_aud_ts_revision"),
                ("revision_reason", "_aud_revision_reason"),
                ("aud_user_id", "_aud_user_id"),
            ]:
                if col_name in aud_col_set:
                    optional_aud_cols.append(F.col(col_name).alias(alias))
                else:
                    optional_aud_cols.append(F.lit(None).cast("string").alias(alias))

            present_mod_cols = [mc for mc in needed_mod_cols if mc in aud_col_set]
            mod_col_selects = [F.col(mc) for mc in present_mod_cols]

            aud_projections[source_name] = (
                source_aud_df.select(
                    *base_aud_select, *optional_aud_cols, *mod_col_selects
                ),
                present_mod_cols,
            )

        # Window for MAX(rev) tiebreaker within each (entity_id, ts) group
        w_tiebreak = Window.partitionBy("_aud_id", "_aud_ts").orderBy(
            F.desc("_aud_rev")
        )

        # Join key: entity id + exact timestamp match
        join_key = (F.col(id_entity_col) == F.col("_aud_id")) & (
            F.col("ts_transaction") == F.col("_aud_ts")
        )

        enriched_parts = []
        for (source_name, mod_col), ev_names in group_to_event_names.items():
            aud_projected, present_mod_cols = aud_projections[source_name]

            ev_slice = enrichable_df.filter(F.col("event_name").isin(ev_names))

            # AUD for insert path (op_cdc='c'): rev_type=0, no mod-flag filter
            aud_insert = (
                aud_projected.filter(F.col("_aud_rev_type") == F.lit(0))
                .withColumn("_rn", F.row_number().over(w_tiebreak))
                .filter(F.col("_rn") == 1)
                .drop("_rn", *present_mod_cols)
            )

            # AUD for update/delete path: mod_col=true, MAX(rev) tiebreaker
            if mod_col in present_mod_cols:
                aud_update_base = aud_projected.filter(F.col(mod_col) == F.lit(True))
            else:
                aud_update_base = aud_projected
            aud_update = (
                aud_update_base.withColumn("_rn", F.row_number().over(w_tiebreak))
                .filter(F.col("_rn") == 1)
                .drop("_rn", *present_mod_cols)
            )

            insert_slice = ev_slice.filter(F.col(cdc_op_col) == F.lit("c"))
            update_slice = ev_slice.filter(F.col(cdc_op_col) != F.lit("c"))

            joined_insert = insert_slice.join(aud_insert, on=join_key, how="left")
            joined_update = update_slice.join(aud_update, on=join_key, how="left")

            combined = joined_insert.unionByName(joined_update)

            # Build payload JSON.
            # aud_values uses create_map so it serialises as a JSON object
            # {"<field_name>": "<value>"} — not a nested string.
            # to_json(struct(MapType)) renders the map inline in the JSON object.
            # Apply lower() so that event names like "ev_STATUS" produce
            # {"status": ...} rather than {"STATUS": ...} in the JSON output.
            aud_values_expr = F.create_map(
                F.lower(F.regexp_replace(F.col("event_name"), "^ev_", "")),
                F.col("value"),
            )

            full_payload_expr = F.to_json(
                F.struct(
                    F.lit(1).alias("payload_version"),
                    F.col(cdc_op_col).alias("op_cdc"),
                    F.col("_aud_rev").alias("rev"),
                    F.col("_aud_rev_type").alias("rev_type"),
                    F.col("_aud_ts_revision").alias("ts_revision"),
                    F.col("_aud_ts_cdc").alias("ts_cdc_transaction"),
                    F.col("_aud_revision_reason").alias("revision_reason"),
                    F.col("_aud_user_id").alias("aud_user_id"),
                    aud_values_expr.alias("aud_values"),
                )
            )

            # For delete events with no AUD match we emit a minimal payload so
            # consumers can still detect the deletion without needing to inspect
            # event_type (which is always "cdc" for all CDC events).
            delete_minimal_payload_expr = F.to_json(
                F.struct(
                    F.lit(1).alias("payload_version"),
                    F.col(cdc_op_col).alias("op_cdc"),
                    F.lit(None).cast("long").alias("rev"),
                    F.lit(None).cast("int").alias("rev_type"),
                    F.lit(None).cast("string").alias("ts_revision"),
                    F.lit(None).cast("string").alias("revision_reason"),
                    F.lit(None).cast("long").alias("aud_user_id"),
                    aud_values_expr.alias("aud_values"),
                )
            )

            combined = combined.withColumn(
                "payload",
                F.when(
                    ~F.isnull("_aud_rev"),
                    full_payload_expr,
                )
                .when(
                    F.col(cdc_op_col) == F.lit("d"),
                    delete_minimal_payload_expr,
                )
                .otherwise(F.lit(None).cast("string")),
            )

            # Drop transient AUD join columns from this batch
            aud_join_cols = [
                "_aud_id",
                "_aud_ts",
                "_aud_rev",
                "_aud_rev_type",
                "_aud_ts_cdc",
                "_aud_ts_revision",
                "_aud_revision_reason",
                "_aud_user_id",
            ]
            cols_to_drop = [c for c in aud_join_cols if c in combined.columns]
            combined = combined.drop(*cols_to_drop)

            enriched_parts.append(combined)

        if not enriched_parts:
            return non_enrichable_df

        enriched_df = reduce(DataFrame.unionByName, enriched_parts)
        return enriched_df.unionByName(non_enrichable_df)

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
