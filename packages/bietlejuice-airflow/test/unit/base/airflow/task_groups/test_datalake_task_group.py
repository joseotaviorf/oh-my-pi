"""
Unit tests for DatalakeTaskGroup data quality path equivalence.

Verifies that the batch _get_data_quality_tables + set lookup produces the same
results as the original artifact_file_exists / data_quality_tests_file_exists_in_composer
calls for various (tree_path, table_name) combinations.
"""

from os import path
from unittest import mock

import pytest

from bietlejuice.base.airflow.task_groups.datalake_task_group import (
    DatalakeTaskGroup,
)


class TestDatalakeTaskGroupDataQualityPathEquivalence:
    """Verify batch data quality lookup matches per-call semantics."""

    @pytest.fixture
    def mock_dag(self):
        dag = mock.MagicMock()
        dag.dag_id = "test_dag"
        return dag

    @pytest.fixture
    def datalake_task_group(self, mock_dag):
        """Create DatalakeTaskGroup with mocked dependencies."""
        with mock.patch(
            "bietlejuice.base.airflow.task_groups.datalake_task_group.ConfigurationService"
        ) as mock_config_svc:
            mock_config_svc.return_value.get_config.return_value = "mock_bucket"
            return DatalakeTaskGroup(
                dag=mock_dag,
                env="forno",
                datalake_bucket="mock_bucket",
                relative_query_path="test_dag",
                spark_jobs_path="/mock/spark/jobs",
            )

    @mock.patch(
        "bietlejuice.base.airflow.task_groups.datalake_task_group.DAGPackagesPathService.list_data_quality_table_paths_in_composer"
    )
    def test_get_data_quality_tables_normalizes_paths(
        self, mock_list_dq, datalake_task_group
    ):
        """Batch method normalizes paths for consistent lookup."""
        mock_list_dq.return_value = {
            "my_table",
            "full/other_table",
            "nested/path/table",
        }
        layer = "clean"

        result = datalake_task_group._get_data_quality_tables(layer)

        assert result == {
            path.normpath("my_table"),
            path.normpath("full/other_table"),
            path.normpath("nested/path/table"),
        }
        mock_list_dq.assert_called_once_with("test_dag", layer)

    @mock.patch(
        "bietlejuice.base.airflow.task_groups.datalake_task_group.DAGPackagesPathService.list_data_quality_table_paths_in_composer"
    )
    @pytest.mark.parametrize(
        "tree_path,table_name,expected_in_set",
        [
            ("", "my_table", True),
            ("full", "other_table", True),
            ("nested/path", "table", True),
            ("", "nonexistent", False),
            ("full", "my_table", False),
            ("", "other_table", False),
        ],
    )
    def test_batch_lookup_equivalent_to_per_call_checks(
        self, mock_list_dq, datalake_task_group, tree_path, table_name, expected_in_set
    ):
        """
        Batch lookup produces same result as artifact_file_exists /
        data_quality_tests_file_exists_in_composer for path equivalence.

        list_data_quality_table_paths_in_composer returns paths relative to
        data_quality/{layer}/, e.g. "my_table" or "full/other_table".
        The original methods check: {dag_path}/data_quality/{layer}/{tree_path}/{table_name}.yml
        So the lookup key must be path.join(tree_path, table_name).
        """
        mock_list_dq.return_value = {
            "my_table",
            "full/other_table",
            "nested/path/table",
        }
        layer = "clean"

        dq_tables = datalake_task_group._get_data_quality_tables(layer)
        lookup_key = path.normpath(path.join(tree_path, table_name))
        actual = lookup_key in dq_tables

        assert actual == expected_in_set

    @mock.patch(
        "bietlejuice.base.airflow.task_groups.datalake_task_group.DAGPackagesPathService.list_data_quality_table_paths_in_composer"
    )
    def test_get_data_quality_tables_caches_per_layer(
        self, mock_list_dq, datalake_task_group
    ):
        """Cache is populated once per layer; subsequent calls do not re-invoke service."""
        mock_list_dq.return_value = {"cached_table"}
        layer = "enrich"

        datalake_task_group._get_data_quality_tables(layer)
        datalake_task_group._get_data_quality_tables(layer)

        mock_list_dq.assert_called_once_with("test_dag", layer)

    # --- _get_config_service cache tests ---

    @mock.patch(
        "bietlejuice.base.airflow.task_groups.datalake_task_group.ConfigurationService"
    )
    def test_get_config_service_caches_per_source(
        self, mock_config_class, datalake_task_group
    ):
        """ConfigurationService is constructed only once per unique source string."""
        mock_instance = mock.MagicMock()
        mock_config_class.return_value = mock_instance

        # act — request the same source twice
        result_1 = datalake_task_group._get_config_service("ebdb")
        result_2 = datalake_task_group._get_config_service("ebdb")

        # assert — same object returned; constructor called only once
        assert result_1 is result_2
        mock_config_class.assert_called_once_with("ebdb")

    @mock.patch(
        "bietlejuice.base.airflow.task_groups.datalake_task_group.ConfigurationService"
    )
    def test_get_config_service_different_sources_not_shared(
        self, mock_config_class, datalake_task_group
    ):
        """Different source strings produce independent ConfigurationService instances."""
        mock_config_class.side_effect = lambda src: mock.MagicMock(name=src)

        # act
        service_ebdb = datalake_task_group._get_config_service("ebdb")
        service_amp = datalake_task_group._get_config_service("amplitude")

        # assert — distinct instances, each source resolved once
        assert service_ebdb is not service_amp
        assert mock_config_class.call_count == 2

    # --- _get_metadata_tables cache tests ---

    @mock.patch(
        "bietlejuice.base.airflow.task_groups.datalake_task_group.DAGMetadataService.list_metadata_table_paths"
    )
    def test_get_metadata_tables_caches_per_layer(
        self, mock_list_meta, datalake_task_group
    ):
        """list_metadata_table_paths is called only once per layer."""
        mock_list_meta.return_value = {"contract", "user"}

        # act — call twice with the same layer
        result_1 = datalake_task_group._get_metadata_tables("enrich")
        result_2 = datalake_task_group._get_metadata_tables("enrich")

        # assert
        assert result_1 == result_2 == {"contract", "user"}
        mock_list_meta.assert_called_once_with("test_dag", "enrich")

    @mock.patch(
        "bietlejuice.base.airflow.task_groups.datalake_task_group.DAGMetadataService.list_metadata_table_paths"
    )
    def test_get_metadata_tables_different_layers_cached_independently(
        self, mock_list_meta, datalake_task_group
    ):
        """Each layer has its own cache entry."""
        mock_list_meta.side_effect = lambda dag, layer: {
            "clean": {"clean_table"},
            "enrich": {"enrich_table"},
        }[layer]

        # act
        clean = datalake_task_group._get_metadata_tables("clean")
        enrich = datalake_task_group._get_metadata_tables("enrich")

        # assert — each layer received the correct set; service called twice total
        assert clean == {"clean_table"}
        assert enrich == {"enrich_table"}
        assert mock_list_meta.call_count == 2

    # --- _has_any_metadata cache tests ---

    @mock.patch(
        "bietlejuice.base.airflow.task_groups.datalake_task_group.DAGMetadataService.get_all_dag_metadata_files"
    )
    def test_has_any_metadata_caches_result(
        self, mock_get_all_files, datalake_task_group
    ):
        """get_all_dag_metadata_files is called only once; subsequent calls use cached bool."""
        mock_get_all_files.return_value = ["some_file.yml"]

        # act — call twice
        result_1 = datalake_task_group._has_any_metadata()
        result_2 = datalake_task_group._has_any_metadata()

        # assert — same result, service invoked once
        assert result_1 is True
        assert result_2 is True
        mock_get_all_files.assert_called_once_with("test_dag")
