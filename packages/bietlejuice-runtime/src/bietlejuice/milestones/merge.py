"""Aggregate milestone events and prepare incremental/bootstrap merge batches."""

from __future__ import annotations

from typing import List

from pyspark.sql import DataFrame
from pyspark.sql import functions as F

from bietlejuice.milestones.contract import MilestoneTableSpec


def aggregate_events(events: DataFrame, spec: MilestoneTableSpec) -> DataFrame:
    """Collapse event rows to one row per entity key set.

    Sets ``ts_first`` / ``ts_last`` and entity pointers from min/max ``ts_event``.
    Sticky carries and ``entity_type`` come from the first-event row.
    Does not set ``milestone_type`` — caller adds it from the registry entry.
    """
    first_fields: List = list(spec.sticky_columns) + [
        "sk_entity",
        "entity_type",
        "ts_event",
    ]
    # Only include optional columns that exist on the events frame.
    first_struct_cols = [c for c in first_fields if c in events.columns]
    if "ts_event" not in first_struct_cols:
        first_struct_cols.append("ts_event")

    last_struct_cols = [c for c in ("sk_entity", "ts_event") if c in events.columns]
    if "ts_event" not in last_struct_cols:
        last_struct_cols.append("ts_event")

    first_row = F.min_by(
        F.struct(*[F.col(c) for c in first_struct_cols]),
        F.col("ts_event"),
    ).alias("first_row")
    last_row = F.max_by(
        F.struct(*[F.col(c) for c in last_struct_cols]),
        F.col("ts_event"),
    ).alias("last_row")

    select_cols = [F.col(k) for k in spec.entity_keys]
    for sticky in spec.sticky_columns:
        select_cols.append(F.col(f"first_row.{sticky}").alias(sticky))
    select_cols.extend(
        [
            F.col("first_row.ts_event").alias("ts_first"),
            F.col("last_row.ts_event").alias("ts_last"),
        ]
    )
    # Always emit optional entity pointer columns so batches from strategies
    # with/without sk_entity / entity_type share one schema for unionByName.
    if "sk_entity" in events.columns:
        select_cols.extend(
            [
                F.col("first_row.sk_entity").alias("sk_entity_first"),
                F.col("last_row.sk_entity").alias("sk_entity_last"),
            ]
        )
    else:
        select_cols.extend(
            [
                F.lit(None).cast("long").alias("sk_entity_first"),
                F.lit(None).cast("long").alias("sk_entity_last"),
            ]
        )
    if "entity_type" in events.columns:
        select_cols.append(F.col("first_row.entity_type").alias("entity_type"))
    else:
        select_cols.append(F.lit(None).cast("string").alias("entity_type"))

    return (
        events.groupBy(*spec.entity_keys).agg(first_row, last_row).select(*select_cols)
    )


def prepare_merge_batch(
    existing: DataFrame,
    aggregated: DataFrame,
    spec: MilestoneTableSpec,
    bootstrap: bool = False,
) -> tuple[DataFrame, DataFrame]:
    """Split aggregated rows into inserts (new keys) and updates.

    Incremental (``bootstrap=False``):
      - keep existing ``ts_first`` / sticky carries / ``sk_entity_first`` / ``entity_type``
      - advance ``ts_last`` / ``sk_entity_last`` only when newer; late events dropped

    Bootstrap (``bootstrap=True``):
      - rewrite timestamps, sticky carries, and entity pointers from aggregated
    """
    join_keys = list(spec.merge_on)
    existing_aliased = existing.alias("e")
    aggregated_aliased = aggregated.alias("a")

    joined = aggregated_aliased.join(existing_aliased, on=join_keys, how="left")

    def _select_from_alias(alias: str, bootstrap_mode: bool) -> List:
        cols = [F.col(f"a.{k}") for k in spec.entity_keys]
        cols.append(F.col("a.milestone_type"))
        for sticky in spec.sticky_columns:
            src = "a" if bootstrap_mode else alias
            cols.append(F.col(f"{src}.{sticky}").alias(sticky))
        if bootstrap_mode:
            cols.extend(
                [
                    F.col("a.ts_first").alias("ts_first"),
                    F.col("a.ts_last").alias("ts_last"),
                ]
            )
        else:
            cols.extend(
                [
                    F.col("e.ts_first").alias("ts_first"),
                    F.col("a.ts_last").alias("ts_last"),
                ]
            )
        if "sk_entity_first" in aggregated.columns:
            if bootstrap_mode:
                cols.extend(
                    [
                        F.col("a.sk_entity_first").alias("sk_entity_first"),
                        F.col("a.sk_entity_last").alias("sk_entity_last"),
                    ]
                )
            else:
                cols.extend(
                    [
                        F.col("e.sk_entity_first").alias("sk_entity_first"),
                        F.col("a.sk_entity_last").alias("sk_entity_last"),
                    ]
                )
        if "entity_type" in aggregated.columns:
            src = "a" if bootstrap_mode else "e"
            cols.append(F.col(f"{src}.entity_type").alias("entity_type"))
        return cols

    inserts = joined.where(F.col("e.ts_first").isNull()).select(
        *_select_from_alias("a", bootstrap_mode=True)
    )

    if bootstrap:
        updates = joined.where(F.col("e.ts_first").isNotNull()).select(
            *_select_from_alias("a", bootstrap_mode=True)
        )
    else:
        updates = joined.where(
            F.col("e.ts_first").isNotNull() & (F.col("a.ts_last") > F.col("e.ts_last"))
        ).select(*_select_from_alias("e", bootstrap_mode=False))

    return inserts, updates
