import pytest

from bietlejuice.base.qube.qube_table_naming import (
    qube_output_base_table_name,
    qube_validation_trino_table_name,
    qube_windowed_table_name,
)


class TestQubeTableNaming:
    @pytest.mark.parametrize(
        "entity,name,expected",
        [
            ("visit", "business_context", "visit_business_context"),
            ("visit", "visit_business_context", "visit_business_context"),
        ],
    )
    def test_output_base_table_name(self, entity, name, expected):
        assert qube_output_base_table_name(entity, name) == expected

    def test_windowed_table_name(self):
        assert qube_windowed_table_name("visit", "business_context", 28) == (
            "visit_business_context_28d"
        )

    def test_validation_trino_table_name(self):
        assert qube_validation_trino_table_name(
            "qube_dimensions", "visit_business_context_28d"
        ) == ("qube_dimensions___visit_business_context_28d")
