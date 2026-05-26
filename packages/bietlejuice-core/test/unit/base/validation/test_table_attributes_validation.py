import pytest

from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class TestTableAttributesValidation:
    @pytest.mark.parametrize(
        "layer,schema,table,expected_table",
        [
            (
                LayerEnum.ENRICH,
                "foo",
                "bar",
                "datalake_foo___bar",
            ),
            (
                LayerEnum.DW,
                "foo",
                "bar",
                "dw_foo___bar",
            ),
            (
                LayerEnum.METRIC,
                "foo",
                "bar",
                "metric_foo___bar",
            ),
        ],
    )
    def test_validation_write_target(self, layer, schema, table, expected_table):
        attributes = TableAttributes(
            {"name": "test_dag"},
            {"custom_schema": schema},
            layer,
            table,
        )

        target_db, target_table = attributes.get_validation_write_target()

        assert target_db == "cluster_validation"
        assert target_table == expected_table
