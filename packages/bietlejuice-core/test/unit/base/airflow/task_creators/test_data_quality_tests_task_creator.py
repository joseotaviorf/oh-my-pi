from unittest import mock

from bietlejuice.base.airflow.task_creators.data_quality_tests_task_creator import (
    DataQualityTestsTaskCreator,
)


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

    def test_appends_resolved_platforms_comma_joined(self):
        creator = self._creator()
        table_attributes = self._table_attributes(
            {"type": "enrich", "has_hive_sync": True}
        )

        params = creator._get_parameters(table_attributes)

        # platforms is the last positional parameter, comma-joined
        assert params[-1] == "databricks,glue,trino"

    def test_core_model_excludes_trino(self):
        creator = self._creator()
        table_attributes = self._table_attributes({"type": "core_model"})

        params = creator._get_parameters(table_attributes)

        assert params[-1] == "databricks,glue"

    def test_table_customization_overrides_workflow(self):
        creator = self._creator()
        table_attributes = self._table_attributes(
            {"type": "enrich", "has_hive_sync": True},
            table_customization={"has_hive_sync": False},
        )

        params = creator._get_parameters(table_attributes)

        assert params[-1] == "databricks,glue"
