"""Generic milestone event / grain contract.

Entity key column names are consumer-chosen via ``merge_on`` (minus
``milestone_type``). Agents may use ``sk_user``; other domains may use
``id_house``, ``sk_contract``, etc.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any, Dict, Optional, Sequence, Tuple

from pyspark.sql import DataFrame
from pyspark.sql import functions as F

MILESTONE_TYPE_COLUMN = "milestone_type"
TS_EVENT_COLUMN = "ts_event"
OPTIONAL_ENTITY_COLUMNS = ("sk_entity", "entity_type")


@dataclass(frozen=True)
class MilestoneTableSpec:
    """Per-target-table grain and sticky-carry configuration."""

    entity_keys: Tuple[str, ...]
    sticky_columns: Tuple[str, ...] = ()

    def __post_init__(self) -> None:
        if not self.entity_keys:
            raise ValueError(
                "m=MilestoneTableSpec, msg=entity_keys must be non-empty "
                "(merge_on minus milestone_type)"
            )
        if MILESTONE_TYPE_COLUMN in self.entity_keys:
            raise ValueError(
                "m=MilestoneTableSpec, msg=milestone_type must not appear in entity_keys"
            )
        overlap = set(self.entity_keys) & set(self.sticky_columns)
        if overlap:
            raise ValueError(
                f"m=MilestoneTableSpec, msg=sticky_columns overlap entity_keys: {sorted(overlap)}"
            )

    @property
    def merge_on(self) -> Tuple[str, ...]:
        return self.entity_keys + (MILESTONE_TYPE_COLUMN,)

    @property
    def required_event_columns(self) -> Tuple[str, ...]:
        return self.entity_keys + self.sticky_columns + (TS_EVENT_COLUMN,)

    @classmethod
    def from_merge_on(
        cls,
        merge_on: Sequence[str],
        sticky_columns: Optional[Sequence[str]] = None,
    ) -> "MilestoneTableSpec":
        keys = [str(c) for c in merge_on]
        if MILESTONE_TYPE_COLUMN not in keys:
            raise ValueError(
                "m=from_merge_on, msg=merge_on must include milestone_type"
            )
        entity_keys = tuple(c for c in keys if c != MILESTONE_TYPE_COLUMN)
        sticky = tuple(str(c) for c in (sticky_columns or ()))
        return cls(entity_keys=entity_keys, sticky_columns=sticky)


@dataclass(frozen=True)
class MilestoneRunContext:
    """Runtime context passed into each milestone strategy."""

    milestone_type: str
    bootstrap: bool
    existing: DataFrame
    scan_predicate: str


def build_scan_predicate(
    existing: DataFrame,
    bootstrap: bool,
    scan: Optional[Dict[str, Any]],
) -> str:
    """Build SQL predicate for incremental source scan.

    Bootstrap or empty existing (first run / no rows for this type): ``1 = 1``.
    Else: ``{ts_column} >= max(ts_last) - lookback_days``.
    """
    if bootstrap:
        return "1 = 1"
    if not scan or not scan.get("ts_column"):
        raise ValueError(
            "m=build_scan_predicate, msg=scan.ts_column required when bootstrap=false"
        )
    if len(existing.head(1)) == 0:
        return "1 = 1"

    lookback_days = int(scan.get("lookback_days", 0))
    ts_column = str(scan["ts_column"])

    wm_row = existing.agg(F.max("ts_last").alias("wm")).collect()[0]
    watermark = wm_row["wm"]
    if watermark is None:
        return "1 = 1"

    if isinstance(watermark, datetime):
        lower = watermark - timedelta(days=lookback_days)
    else:
        lower = datetime.fromisoformat(str(watermark)) - timedelta(days=lookback_days)

    lower_lit = lower.strftime("%Y-%m-%d %H:%M:%S")
    return f"{ts_column} >= TIMESTAMP('{lower_lit}')"
