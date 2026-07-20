from unittest import mock

from bietlejuice.base.dependencies.bietlejuice_dependency_helper import (
    BietlejuiceDependencyHelper,
)

# Graph used by reverse-lookup tests:
#   clean → enrich → dw_a
#                 → enrich_mid → dw_b
#   clean → metric_x  (non-dw)
_SAMPLE_DEPS = {
    "bietlejuice.enrich_source": [
        "bietlejuice.clean_source:load-clean-table:first-run-of-day",
    ],
    "bietlejuice.enrich_mid": [
        "bietlejuice.enrich_source:load-enrich-table:first-run-of-day",
    ],
    "bietlejuice.dw_a": [
        "bietlejuice.enrich_source:load-enrich-table:first-run-of-day",
    ],
    "bietlejuice.dw_b": [
        "bietlejuice.enrich_mid:load-enrich-mid:first-run-of-day",
    ],
    "bietlejuice.metric_x": [
        "bietlejuice.clean_source:load-clean-table:first-run-of-day",
    ],
}


class TestBietlejuiceDependencyHelperDownstream:
    def test_build_downstream_index_inverts_direct_edges(self):
        index = BietlejuiceDependencyHelper.build_downstream_index(_SAMPLE_DEPS)
        assert index["bietlejuice.clean_source"] == {
            "bietlejuice.enrich_source",
            "bietlejuice.metric_x",
        }
        assert index["bietlejuice.enrich_source"] == {
            "bietlejuice.enrich_mid",
            "bietlejuice.dw_a",
        }
        assert "bietlejuice.dw_a" not in index  # leaf: no dependents

    def test_build_downstream_index_flattens_nested_any_all(self):
        deps = {
            "bietlejuice.dw_nested": {
                "any": [
                    "bietlejuice.enrich_a:load-enrich-a",
                    {"all": ["bietlejuice.enrich_b:load-enrich-b"]},
                ]
            }
        }
        index = BietlejuiceDependencyHelper.build_downstream_index(deps)
        assert index["bietlejuice.enrich_a"] == {"bietlejuice.dw_nested"}
        assert index["bietlejuice.enrich_b"] == {"bietlejuice.dw_nested"}

    def test_build_downstream_index_empty_and_none(self):
        assert BietlejuiceDependencyHelper.build_downstream_index({}) == {}
        assert BietlejuiceDependencyHelper.build_downstream_index(None) == {}

    def test_find_downstream_dags_direct_only(self):
        result = BietlejuiceDependencyHelper.find_downstream_dags(
            "bietlejuice.enrich_source",
            _SAMPLE_DEPS,
            transitive=False,
        )
        assert result == ["bietlejuice.dw_a", "bietlejuice.enrich_mid"]

    def test_find_downstream_dags_transitive(self):
        result = BietlejuiceDependencyHelper.find_downstream_dags(
            "bietlejuice.clean_source",
            _SAMPLE_DEPS,
            transitive=True,
        )
        assert result == [
            "bietlejuice.dw_a",
            "bietlejuice.dw_b",
            "bietlejuice.enrich_mid",
            "bietlejuice.enrich_source",
            "bietlejuice.metric_x",
        ]

    def test_find_downstream_dags_excludes_self_and_is_cycle_safe(self):
        cyclic = {
            "bietlejuice.a": ["bietlejuice.b:load-x"],
            "bietlejuice.b": ["bietlejuice.a:load-y"],
        }
        result = BietlejuiceDependencyHelper.find_downstream_dags(
            "bietlejuice.a", cyclic, transitive=True
        )
        assert result == ["bietlejuice.b"]

    def test_find_downstream_dags_reuses_prebuilt_index(self):
        index = BietlejuiceDependencyHelper.build_downstream_index(_SAMPLE_DEPS)
        result = BietlejuiceDependencyHelper.find_downstream_dags(
            "bietlejuice.enrich_source",
            downstream_index=index,
            transitive=False,
        )
        assert result == ["bietlejuice.dw_a", "bietlejuice.enrich_mid"]

    def test_find_downstream_dw_dags_filters_prefix(self):
        result = BietlejuiceDependencyHelper.find_downstream_dw_dags(
            "bietlejuice.clean_source",
            _SAMPLE_DEPS,
        )
        assert result == ["bietlejuice.dw_a", "bietlejuice.dw_b"]

    def test_find_downstream_dw_dags_empty_when_no_dw_dependents(self):
        result = BietlejuiceDependencyHelper.find_downstream_dw_dags(
            "bietlejuice.metric_x",
            _SAMPLE_DEPS,
        )
        assert result == []

    @mock.patch.object(BietlejuiceDependencyHelper, "read_dependencies")
    def test_find_downstream_dags_reads_file_when_no_deps_passed(self, mock_read):
        mock_read.return_value = _SAMPLE_DEPS
        result = BietlejuiceDependencyHelper.find_downstream_dags(
            "bietlejuice.enrich_source", transitive=False
        )
        mock_read.assert_called_once()
        assert result == ["bietlejuice.dw_a", "bietlejuice.enrich_mid"]


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

    def test_load_into_redshift_dw_task_uses_get_table_name_from_dw_task(self):
        # Redshift path calls _get_table_name_from_dw_task; fact- case
        task_name = "bietlejuice.dw_supply:load-into-redshift-dw-fact-supply-events"
        dag_name, table = (
            BietlejuiceDependencyHelper.extract_dag_and_table_from_task_name(task_name)
        )
        assert dag_name == "dw_supply"
        assert table == "dw:fact_supply_events"
