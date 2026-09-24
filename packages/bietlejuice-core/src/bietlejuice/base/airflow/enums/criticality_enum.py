from __future__ import annotations

from collections.abc import Iterable
from typing import ClassVar


class CriticalityEnum:
    CRITICAL = "Critical"
    HIGH = "High"
    MEDIUM = "Medium"
    LOW = "Low"
    DEFAULT = MEDIUM
    PAGING = (CRITICAL, HIGH)
    DEFAULT_DEADLINE_BY_TIER: ClassVar[dict[str, str]] = {
        CRITICAL: "08:00",
        HIGH: "08:00",
        MEDIUM: "11:00",
        LOW: "11:00",
    }
    _TIER_ORDER: ClassVar[dict[str, int]] = {CRITICAL: 3, HIGH: 2, MEDIUM: 1, LOW: 0}
    _OPSGENIE_PRIORITY: ClassVar[dict[str, str]] = {
        CRITICAL: "P1",
        HIGH: "P2",
        MEDIUM: "P3",
        LOW: "P4",
    }

    @classmethod
    def highest(cls, values: Iterable[str | None]) -> str:
        tiers = [value for value in values if value in cls._TIER_ORDER]
        if not tiers:
            return cls.DEFAULT
        return max(tiers, key=lambda tier: cls._TIER_ORDER[tier])

    @classmethod
    def default_deadline(cls, tier: str | None) -> str:
        return cls.DEFAULT_DEADLINE_BY_TIER.get(
            tier, cls.DEFAULT_DEADLINE_BY_TIER[cls.MEDIUM]
        )

    @classmethod
    def get_available_enum_values(cls) -> list[str]:
        return [cls.CRITICAL, cls.HIGH, cls.MEDIUM, cls.LOW]

    @classmethod
    def parse(cls, value: str | None, *, context: str) -> str:
        if value is None:
            return cls.DEFAULT
        if value not in cls.get_available_enum_values():
            raise ValueError(
                f"Invalid criticality {value!r} for {context}; "
                f"expected one of {cls.get_available_enum_values()}."
            )
        return value

    _PRIORITY_WEIGHT: ClassVar[dict[str, int]] = {
        CRITICAL: 100,
        HIGH: 50,
        MEDIUM: 1,
        LOW: 1,
    }

    @classmethod
    def effective_tier(cls, dag_args: dict, workflow_args: dict) -> str:
        """Highest of the DAG's declared criticality and its tables' criticalities."""
        return cls.highest(
            [dag_args.get("criticality")]
            + [
                customization.get("criticality")
                for customization in (
                    workflow_args.get("tables_customization") or {}
                ).values()
                if isinstance(customization, dict)
            ]
        )

    @classmethod
    def priority_weight(cls, tier: str) -> int:
        return cls._PRIORITY_WEIGHT[tier]

    @classmethod
    def to_opsgenie_priority(cls, value: str) -> str:
        return cls._OPSGENIE_PRIORITY[value]


CRITICALITY_TAG_PREFIX = "criticality:"
SLA_DEADLINE_TAG_PREFIX = "sla_deadline_localtime:"
# Must not contain the substring "criticality:". dag.sql extracts the declared
# tier with REGEXP_EXTRACT(tags, 'criticality:(Critical|High|Medium|Low)'), which
# would match inside a tag such as effective_criticality:Critical.
EFFECTIVE_TIER_TAG_PREFIX = "effective_tier:"
SLA_DEADLINE_PATTERN = r"^([01]\d|2[0-3]):[0-5]\d$"
FRESHNESS_MAX_STALENESS_TAG_PREFIX = "freshness_max_staleness_minutes:"
FRESHNESS_ACTIVE_WINDOW_TAG_PREFIX = "freshness_active_window_localtime:"
FRESHNESS_ACTIVE_WINDOW_PATTERN = (
    r"^([01]\d|2[0-3]):[0-5]\d-(([01]\d|2[0-3]):[0-5]\d|24:00)$"
)
DEFAULT_FRESHNESS_ACTIVE_WINDOW = "00:00-24:00"
