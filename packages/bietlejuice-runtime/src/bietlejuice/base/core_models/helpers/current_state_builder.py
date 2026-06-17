"""CurrentStateBuilder materialises the current state of an entity from a history of events.

Given a narrow, fixed-schema event history (one row per field change), this helper
collapses it into a wide current-state snapshot: one row per entity grain, holding the
latest value of each tracked column. It is the read-side counterpart of ``HistoryBuilder``
and is entity-agnostic, so any Core Model Spark job following the history-first pattern can
reuse it.

The entity grain may be a single column (e.g. ``"id_business_unit"``) or a composite,
multi-column grain (e.g. ``["id_region", "id_business_unit"]``). Composite-grain history
tables persist the grain as separate columns, so the builder partitions, joins and groups
on the full key list natively.
"""

from functools import reduce
from operator import and_
from typing import Dict, List, Union

from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from pyspark.sql.window import Window

from bietlejuice.base.core_models.helpers.event_config_resolution import (
    resolve_event_name,
)


class CurrentStateBuilder:
    """Materialises a wide current-state row from a narrow event history.

    Given a history DataFrame with the fixed schema
    (``id_event``, ``id_{entity}``, ``event_name``, ``value``,
    ``ts_transaction``, ...) this helper:

    1. Identifies entities that changed inside the load window.
    2. For those entities retrieves the **latest** value per
       ``event_name`` across the full history. Latest is decided by
       ``ts_transaction`` (the history grain guarantees it is unique per
       ``(entity_grain, event_name)``), with ``value`` as a content-bearing
       tie-break for any residual same-ts duplicates.
    3. Pivots the narrow rows into one wide row per entity grain with
       correctly typed columns.
    4. Optionally validates self-consistency of the output (grain
       uniqueness and key completeness).

    The output is entity-agnostic and can be used by any Core Model
    Spark job that follows the history-first pattern. The entity grain
    may be a single column or a composite, multi-column key.
    """

    REQUIRED_CONFIG_KEYS = {"target_col", "target_type"}

    @staticmethod
    def build_current_state(
        history_df: DataFrame,
        entity_id_col: Union[str, List[str]],
        event_configs: List[Dict[str, str]],
        load_start_date: str = None,
        load_end_date: str = None,
        validate: bool = True,
        require_non_empty: bool = False,
    ) -> DataFrame:
        """Build the current-state wide DataFrame from history events.

        Args:
            history_df: Narrow history DataFrame (must contain at least
                the entity grain column(s), ``event_name``, ``value``,
                ``ts_transaction``).
            entity_id_col: Column (or list of columns) holding the entity
                grain (e.g. ``"id_contract"`` or
                ``["id_region", "id_business_unit"]``).
            event_configs: List of dicts with ``target_col`` and ``target_type``,
                and optional ``event_name`` (defaults to ``ev_{target_col}``).
            load_start_date: Optional inclusive lower bound
                (``ts_transaction`` cast to date).
            load_end_date: Optional inclusive upper bound.
            validate: When ``True`` (default), run self-consistency guards
                on the output (grain uniqueness and key completeness).
            require_non_empty: When ``True``, fail if the output is empty.
                Enforced independently of ``validate`` (a caller that
                requires output still fails on empty even with the
                self-consistency guards disabled). Off by default so an empty
                load window yields an empty DataFrame.

        Returns:
            Wide DataFrame with the entity grain column(s) plus one column
            per ``target_col``, cast to ``target_type``.
        """
        id_cols = CurrentStateBuilder._normalize_id_cols(entity_id_col)

        CurrentStateBuilder._validate_event_configs(event_configs)

        changed_entities = CurrentStateBuilder._find_changed_entities(
            history_df, id_cols, load_start_date, load_end_date
        )

        event_names = [
            resolve_event_name(ec, index=i) for i, ec in enumerate(event_configs)
        ]
        latest_df = CurrentStateBuilder._get_latest_values(
            history_df, id_cols, changed_entities, event_names
        )

        result = CurrentStateBuilder._pivot_and_cast(latest_df, id_cols, event_configs)

        if validate:
            CurrentStateBuilder._validate_output(result, id_cols, require_non_empty)
        elif require_non_empty and len(result.head(1)) == 0:
            # ``require_non_empty`` is honored independently of ``validate``: a
            # caller that explicitly requires output must still fail on empty
            # even when the self-consistency guards are disabled.
            raise ValueError("current state is empty")

        return result

    @staticmethod
    def _normalize_id_cols(entity_id_col: Union[str, List[str]]) -> List[str]:
        id_cols = (
            [entity_id_col] if isinstance(entity_id_col, str) else list(entity_id_col)
        )
        if not id_cols:
            raise ValueError("entity_id_col must not be empty")
        if len(id_cols) != len(set(id_cols)):
            raise ValueError(f"entity_id_col has duplicate columns: {id_cols}")
        return id_cols

    @staticmethod
    def _validate_event_configs(event_configs: List[Dict[str, str]]) -> None:
        if not event_configs:
            raise ValueError("event_configs must not be empty")
        seen_target_cols = set()
        seen_event_names = set()
        for i, ec in enumerate(event_configs):
            missing = CurrentStateBuilder.REQUIRED_CONFIG_KEYS - set(ec.keys())
            if missing:
                raise ValueError(f"event_configs[{i}] missing required keys: {missing}")
            event_name = resolve_event_name(ec, index=i)

            # Duplicate target_col / event_name would collide in the pivot and
            # produce a wrong or ambiguous output column, so fail fast.
            target_col = ec["target_col"]
            if target_col in seen_target_cols:
                raise ValueError(
                    f"event_configs[{i}] has duplicate target_col: {target_col!r}"
                )
            seen_target_cols.add(target_col)

            if event_name in seen_event_names:
                raise ValueError(
                    f"event_configs[{i}] has duplicate event_name: {event_name!r}"
                )
            seen_event_names.add(event_name)

    @staticmethod
    def _find_changed_entities(
        history_df: DataFrame,
        id_cols: List[str],
        load_start_date: str,
        load_end_date: str,
    ) -> DataFrame:
        if load_start_date and load_end_date:
            return (
                history_df.filter(
                    (
                        F.col("ts_transaction").cast("date")
                        >= F.lit(load_start_date).cast("date")
                    )
                    & (
                        F.col("ts_transaction").cast("date")
                        <= F.lit(load_end_date).cast("date")
                    )
                )
                .select(*id_cols)
                .distinct()
            )
        return history_df.select(*id_cols).distinct()

    @staticmethod
    def _get_latest_values(
        history_df: DataFrame,
        id_cols: List[str],
        changed_entities: DataFrame,
        event_names: List[str],
    ) -> DataFrame:
        filtered = history_df.join(changed_entities, id_cols, "inner").filter(
            F.col("event_name").isin(event_names)
        )

        # Determinism comes primarily from the upstream history grain: every
        # historical core model persists at most one row per
        # ``(entity_grain, event_name, ts_transaction)`` (HistoryBuilder
        # canonicalization + the merge key), so ``ts_transaction`` alone already
        # picks a unique latest row. ``value`` is added as a content-bearing
        # tie-break that still resolves genuine same-ts duplicates (e.g. the
        # listing first-run direct-write path, which skips canonicalization)
        # deterministically. ``id_event`` is intentionally NOT used: it is a
        # hash of ``(grain || event_name || ts_transaction)``, i.e. collinear
        # with the partition + order keys, so it can never break a ts-tie.
        order_cols = [
            F.col("ts_transaction").desc(),
            F.col("value").desc_nulls_last(),
        ]

        w = Window.partitionBy(*id_cols, "event_name").orderBy(*order_cols)
        return (
            filtered.withColumn("_rn", F.row_number().over(w))
            .filter(F.col("_rn") == 1)
            .drop("_rn")
        )

    @staticmethod
    def _pivot_and_cast(
        latest_df: DataFrame,
        id_cols: List[str],
        event_configs: List[Dict[str, str]],
    ) -> DataFrame:
        event_names = [
            resolve_event_name(ec, index=i) for i, ec in enumerate(event_configs)
        ]
        event_map = {
            resolve_event_name(ec, index=i): (ec["target_col"], ec["target_type"])
            for i, ec in enumerate(event_configs)
        }

        pivoted = (
            latest_df.groupBy(*id_cols)
            .pivot("event_name", event_names)
            .agg(F.first("value"))
        )

        for event_name, (target_col, target_type) in event_map.items():
            if event_name in pivoted.columns:
                pivoted = pivoted.withColumn(
                    target_col,
                    F.col(f"`{event_name}`").cast(target_type),
                )
                if event_name != target_col:
                    pivoted = pivoted.drop(event_name)
            else:
                pivoted = pivoted.withColumn(target_col, F.lit(None).cast(target_type))

        return pivoted

    @staticmethod
    def _validate_output(
        df: DataFrame,
        id_cols: List[str],
        require_non_empty: bool = False,
    ) -> None:
        """Self-consistency guards on the current-state output.

        Enforces that every grain key column is non-null and that the grain
        is unique (one row per entity). Computed in a single aggregation
        pass. Raises ``ValueError`` on violation, matching the in-builder
        validation style.
        """
        all_keys_present = reduce(and_, [F.col(c).isNotNull() for c in id_cols])
        stats = df.agg(
            F.count(F.lit(1)).alias("total"),
            F.count(F.when(all_keys_present, F.lit(1))).alias("non_null_keys"),
            F.countDistinct(*[F.col(c) for c in id_cols]).alias("distinct_keys"),
        ).collect()[0]

        total = stats["total"]
        non_null_keys = stats["non_null_keys"]
        distinct_keys = stats["distinct_keys"]

        if non_null_keys != total:
            raise ValueError(
                f"current state has {total - non_null_keys} row(s) with a null grain "
                f"key column among {id_cols}"
            )
        if distinct_keys != total:
            raise ValueError(
                f"current state grain {id_cols} is not unique: {total} row(s) but "
                f"{distinct_keys} distinct key(s)"
            )
        if require_non_empty and total == 0:
            raise ValueError("current state is empty")
