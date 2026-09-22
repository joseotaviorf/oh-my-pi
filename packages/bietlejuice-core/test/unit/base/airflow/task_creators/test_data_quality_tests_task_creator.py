from unittest import mock

from bietlejuice.base.airflow.task_creators.data_quality_tests_task_creator import (
    DataQualityTestsTaskCreator,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class TestDataQualityTestsTaskCreator:
    def _creator(self):
        context = mock.MagicMock()
        context.environment = "prod"
        context.execution_date = "2021-10-25"
        context.dag_args = {"name": "my_dag"}
        config_service = mock.MagicMock()
        config_service.get_config.return_value = "inmetro-bucket"
        return DataQualityTestsTaskCreator(context, config_service)

    def _table_attributes(self, workflow_args, table_customization=None):
        table_attributes = mock.MagicMock()
        table_attributes.workflow_args = workflow_args
        table_attributes.table_customization = table_customization or {}
        table_attributes.layer.value = "enrich"
        table_attributes.table_name = "my_table"
        return table_attributes

    def test_appends_resolved_platforms_as_named_flag(self):
        creator = self._creator()
        table_attributes = self._table_attributes(
            {"type": "enrich", "has_hive_sync": True}
        )

        params = creator._get_parameters(table_attributes)

        # platforms is passed as a NAMED flag (never a trailing positional), so
        # the empty tree-path arg dropped on EMR cannot shift it into another slot.
        assert params[-2:] == ["--platforms", "databricks,glue,trino"]

    def test_core_model_excludes_trino(self):
        creator = self._creator()
        table_attributes = self._table_attributes({"type": "core_model"})

        params = creator._get_parameters(table_attributes)

        assert params[-2:] == ["--platforms", "databricks,glue"]

    def test_table_customization_overrides_workflow(self):
        creator = self._creator()
        table_attributes = self._table_attributes(
            {"type": "enrich", "has_hive_sync": True},
            table_customization={"has_hive_sync": False},
        )

        params = creator._get_parameters(table_attributes)

        assert params[-2:] == ["--platforms", "databricks,glue"]

    @mock.patch(
        "bietlejuice.base.airflow.task_creators."
        "data_quality_tests_task_creator.resolve_platforms",
        return_value=[],
    )
    def test_omits_platforms_flag_when_empty(self, _mock_resolve):
        creator = self._creator()
        table_attributes = self._table_attributes({"type": "query_view"})

        params = creator._get_parameters(table_attributes)

        # no platforms -> no flag; params end at the tree-path arg
        assert "--platforms" not in params
        assert params[-1] == ""

    def test_task_params_carry_resolved_table_criticality(self):
        creator = self._creator()
        task = mock.MagicMock()
        task.params = {}
        creator._create_spark_job_task = mock.MagicMock(return_value=task)

        declared_critical = TableAttributes(
            dag_args={"name": "test_dag", "criticality": "High"},
            workflow_args={"type": "enrich"},
            layer=LayerEnum.ENRICH,
            table_name="listed_table",
            table_customization={"criticality": "Critical"},
        )
        inherits_dag = TableAttributes(
            dag_args={"name": "test_dag", "criticality": "High"},
            workflow_args={"type": "enrich"},
            layer=LayerEnum.ENRICH,
            table_name="sibling_table",
        )

        assert (
            creator.create_task(declared_critical).params["criticality"] == "Critical"
        )
        assert "table_name" not in creator.create_task(declared_critical).params
        task.params = {}
        assert creator.create_task(inherits_dag).params["criticality"] == "High"
