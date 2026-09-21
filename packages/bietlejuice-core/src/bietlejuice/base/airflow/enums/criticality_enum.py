from __future__ import annotations

from typing import ClassVar


class CriticalityEnum:
    CRITICAL = "Critical"
    HIGH = "High"
    MEDIUM = "Medium"
    LOW = "Low"
    DEFAULT = MEDIUM
    PAGING = (CRITICAL, HIGH)
    _OPSGENIE_PRIORITY: ClassVar[dict[str, str]] = {
        CRITICAL: "P1",
        HIGH: "P2",
        MEDIUM: "P3",
        LOW: "P4",
    }

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

    @classmethod
    def to_opsgenie_priority(cls, value: str) -> str:
        return cls._OPSGENIE_PRIORITY[value]


CRITICALITY_TAG_PREFIX = "criticality:"
SLA_DEADLINE_TAG_PREFIX = "sla_deadline_localtime:"
SLA_DEADLINE_PATTERN = r"^([01]\d|2[0-3]):[0-5]\d$"
