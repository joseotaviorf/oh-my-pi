import pytest

from bietlejuice.base.airflow.enums.criticality_enum import (
    CriticalityEnum,
)


class TestCriticalityEnum:
    def test_parse_none_returns_medium(self):
        assert CriticalityEnum.parse(None, context="dag") == "Medium"

    def test_parse_bogus_raises(self):
        with pytest.raises(ValueError, match="Invalid criticality 'Bogus'"):
            CriticalityEnum.parse("Bogus", context="dag foo")

    def test_to_opsgenie_priority_mapping(self):
        assert CriticalityEnum.to_opsgenie_priority("Critical") == "P1"
        assert CriticalityEnum.to_opsgenie_priority("High") == "P2"
        assert CriticalityEnum.to_opsgenie_priority("Medium") == "P3"
        assert CriticalityEnum.to_opsgenie_priority("Low") == "P4"

    def test_paging_levels(self):
        assert CriticalityEnum.PAGING == ("Critical", "High")
