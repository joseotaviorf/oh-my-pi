from unittest import mock

from bietlejuice.base.dependencies.bietlejuice_dependency_helper import (
    BietlejuiceDependencyHelper,
)


class TestBietlejuiceDependencyHelperExtractDagAndTable:
    """Tests for extract_dag_and_table_from_task_name and _get_table_name_from_dw_task."""

    def test_dw_task_with_fact_prefix_returns_fact_table(self):
        # fact- in task: extract fact_* and return layer:table
        task_name = "bietlejuice.dw_supply:load-dw-growth-fact-supply-events"
        dag_name, table = (
            BietlejuiceDependencyHelper.extract_dag_and_table_from_task_name(task_name)
        )
        assert dag_name == "dw_supply"
        assert table == "dw:fact_supply_events"

    def test_dw_task_with_dim_prefix_returns_dim_table(self):
        # dim- in task: extract dim_* and return layer:table
        task_name = "bietlejuice.dw_rent:load-dw-rent-dim-contract"
        dag_name, table = (
            BietlejuiceDependencyHelper.extract_dag_and_table_from_task_name(task_name)
        )
        assert dag_name == "dw_rent"
        assert table == "dw:dim_contract"

    @mock.patch(
        "bietlejuice.base.dependencies.bietlejuice_dependency_helper.FileService.get_dict_from_yaml_file"
    )
    @mock.patch("bietlejuice.base.dependencies.bietlejuice_dependency_helper.isfile")
    @mock.patch(
        "bietlejuice.base.dependencies.bietlejuice_dependency_helper.DAGPackagesPathService.get_dag_path"
    )
    def test_dw_task_without_fact_dim_strips_schema_when_declaration_has_custom_schema(
        self, mock_get_dag_path, mock_isfile, mock_get_yaml
    ):
        # obt_supply-like: task is growth-obt-supply, custom_schema growth -> obt_supply
        mock_get_dag_path.return_value = "/path/to/dags/growth/dw_supply"
        mock_isfile.return_value = True
        mock_get_yaml.return_value = {
            "workflow": {"custom_schema": "growth"},
        }
        task_name = "bietlejuice.dw_supply:load-dw-growth-obt-supply"
        dag_name, table = (
            BietlejuiceDependencyHelper.extract_dag_and_table_from_task_name(task_name)
        )
        assert dag_name == "dw_supply"
        assert table == "dw:obt_supply"

    @mock.patch(
        "bietlejuice.base.dependencies.bietlejuice_dependency_helper.DAGPackagesPathService.get_dag_path"
    )
    def test_dw_task_without_fact_dim_fallback_when_no_dag_path(
        self, mock_get_dag_path
    ):
        # No declaration path -> fallback to dag_context strip
        mock_get_dag_path.return_value = None
        task_name = "bietlejuice.dw_supply:load-dw-obt-supply"
        dag_name, table = (
            BietlejuiceDependencyHelper.extract_dag_and_table_from_task_name(task_name)
        )
        assert dag_name == "dw_supply"
        # Fallback: task obt-supply -> obt_supply, dag_context supply -> no supply_ to strip
        assert table == "dw:obt_supply"

    @mock.patch(
        "bietlejuice.base.dependencies.bietlejuice_dependency_helper.FileService.get_dict_from_yaml_file"
    )
    @mock.patch("bietlejuice.base.dependencies.bietlejuice_dependency_helper.isfile")
    @mock.patch(
        "bietlejuice.base.dependencies.bietlejuice_dependency_helper.DAGPackagesPathService.get_dag_path"
    )
    def test_dw_task_without_fact_dim_fallback_when_declaration_missing_custom_schema(
        self, mock_get_dag_path, mock_isfile, mock_get_yaml
    ):
        mock_get_dag_path.return_value = "/path/to/dags/growth/dw_supply"
        mock_isfile.return_value = True
        mock_get_yaml.return_value = {"workflow": {}}
        task_name = "bietlejuice.dw_supply:load-dw-growth-obt-supply"
        dag_name, table = (
            BietlejuiceDependencyHelper.extract_dag_and_table_from_task_name(task_name)
        )
        assert dag_name == "dw_supply"
        # No custom_schema -> fallback: growth_obt_supply, dag_context supply -> growth_obt_supply
        assert table == "dw:growth_obt_supply"

    @mock.patch(
        "bietlejuice.base.dependencies.bietlejuice_dependency_helper.DAGPackagesPathService.get_dag_path"
    )
    def test_dw_task_without_fact_dim_fallback_when_declaration_file_missing(
        self, mock_get_dag_path
    ):
        mock_get_dag_path.return_value = "/path/to/dags/growth/dw_supply"
        with mock.patch(
            "bietlejuice.base.dependencies.bietlejuice_dependency_helper.isfile",
            return_value=False,
        ):
            task_name = "bietlejuice.dw_supply:load-dw-growth-obt-supply"
            dag_name, table = (
                BietlejuiceDependencyHelper.extract_dag_and_table_from_task_name(
                    task_name
                )
            )
        assert dag_name == "dw_supply"
        assert table == "dw:growth_obt_supply"
