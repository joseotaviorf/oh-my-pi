import re
from os import path
from unittest import mock

import pytest

from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.services.dag_metadata_service import DAGMetadataService

DAG_PACKAGES_ROOT = "/tmp/dags"


class TestDAGMetadataService:
    @pytest.mark.parametrize(
        "dag_manual_mapping", (None, {"test_dag": {"layer": {"database_name": "db"}}})
    )
    def test__init__(self, dag_manual_mapping):
        # act
        service = DAGMetadataService(dag_manual_mapping=dag_manual_mapping)

        # assert
        assert service._STAGING_LAYERS == {
            LayerEnum.DW_STAGING.value,
            LayerEnum.CLEAN_STAGING.value,
        }
        assert service._DAG_PATH_REGEX == re.compile(
            r"dags/(?P<source>\w+)(?:/(?P<context>\w+))?/(?P<dag>\w+)\.py"
        )
        assert service._DAG_OWNER_REGEX == re.compile(r'"owner": ([\w.]*)[,|\n]?')
        assert service._RAW_LAYER_MATCH_REGEX == re.compile(
            "build_raw_task_group_for_all_tables|build_raw_task_group_for_single_table|sync-hive-metastore-raw|sync-metadata-raw"
        )
        assert service._CLEAN_LAYER_MATCH_REGEX == re.compile(
            "sync-hive-metastore-clean|build_clean_task_group|sync-metadata-clean"
        )
        assert service._BUILD_TASK_GROUP_LAYER_REGEX == re.compile(
            r"build_task_group_from_sql_files.*?layer ?= ?LayerEnum\.(\w+)",
            flags=re.DOTALL,
        )
        assert service._SYNC_METASTORE_PARAMETERS == re.compile(
            r"sync_metadata\.py.*?\"parameters\": ?\[(.*?)]|sync_metastore_tables_structure\.py.*?\"parameters\": ?\[(.*?)]",
            flags=re.DOTALL,
        )
        assert service._GENERIC_TARGET_DATABASE_NAME == re.compile(
            r"target_database_base_name ?= ?(\w+)"
        )
        assert service._DW_TASK_GROUP_SCHEMA == re.compile(
            r"DWTaskGroup.*?dw_schema ?= ?(\w*)", flags=re.DOTALL
        )

    @pytest.mark.parametrize(
        "source, context, expected_intermediate_path",
        [
            ("dag_source", "dag_source", None),
            ("dag_source", "dag_context", "dag_source/dag_context"),
        ],
    )
    def test__get_intermediate_path(self, source, context, expected_intermediate_path):
        # arrange
        service = DAGMetadataService()

        # act
        result = service._get_intermediate_path(source, context)

        # assert
        assert result == expected_intermediate_path

    @pytest.mark.parametrize("dag_name", ("any_dag_name"))
    @mock.patch("bietlejuice.services.dag_metadata_service.glob")
    def test__get_dag_file_path(self, mocked_glob, dag_name):
        # arrange
        expected_path = f"{DAG_PACKAGES_ROOT}/example/{dag_name}.py"
        mocked_glob.glob.return_value = [expected_path]
        service = DAGMetadataService()

        # act
        result = service._get_dag_file_path(dag_name)

        # assert
        assert result == expected_path

    @mock.patch("bietlejuice.services.dag_metadata_service.glob")
    @mock.patch.object(DAGPackagesPathService, "get_dag_path")
    def test_metadata_file_exists(self, mocked_get_dag_path, mocked_glob):
        # arrange
        mocked_glob.glob.return_value = [
            f"{DAG_PACKAGES_ROOT}/example/metadata/clean/example_table.yaml"
        ]

        mocked_get_dag_path.return_value = f"{DAG_PACKAGES_ROOT}/example"

        # act
        exists = DAGMetadataService.metadata_file_exists(
            "example", LayerEnum.CLEAN.value, "example_table"
        )

        # assert
        assert exists

    @mock.patch("bietlejuice.services.dag_metadata_service.glob")
    @mock.patch.object(DAGPackagesPathService, "get_dag_path")
    def test_metadata_file_does_not_exists(self, mocked_get_dag_path, mocked_glob):
        # arrange
        mocked_glob.glob.return_value = []

        mocked_get_dag_path.return_value = f"{DAG_PACKAGES_ROOT}/example"

        # act
        exists = DAGMetadataService.metadata_file_exists(
            "example", LayerEnum.CLEAN.value, "non_existing_example_table"
        )

        # assert
        assert not exists

    @mock.patch("bietlejuice.services.dag_metadata_service.glob")
    @mock.patch.object(DAGPackagesPathService, "get_dag_path")
    def test_metadata_folder_exists(self, mocked_get_dag_path, mocked_glob):
        # arrange
        mocked_glob.glob.return_value = [f"{DAG_PACKAGES_ROOT}/example/metadata/clean"]

        mocked_get_dag_path.return_value = f"{DAG_PACKAGES_ROOT}/example"

        # act
        exists = DAGMetadataService.metadata_file_exists(
            "example", LayerEnum.CLEAN.value, None, True
        )

        # assert
        assert exists

    @mock.patch("bietlejuice.services.dag_metadata_service.glob")
    @mock.patch.object(DAGPackagesPathService, "get_dag_path")
    def test_metadata_folder_does_not_exists(self, mocked_get_dag_path, mocked_glob):
        # arrange
        mocked_glob.glob.return_value = []

        mocked_get_dag_path.return_value = f"{DAG_PACKAGES_ROOT}/example"

        # act
        exists = DAGMetadataService.metadata_file_exists(
            "example", LayerEnum.CLEAN.value, None, True
        )

        # assert
        assert not exists


class TestListMetadataTablePaths:
    """Unit tests for DAGMetadataService.list_metadata_table_paths."""

    @mock.patch("bietlejuice.services.dag_metadata_service.os.path.isdir")
    @mock.patch.object(DAGPackagesPathService, "get_dag_path")
    def test_returns_empty_set_when_both_dirs_absent(
        self, mock_get_dag_path, mock_isdir
    ):
        # arrange — neither primary nor legacy directory exists
        mock_get_dag_path.return_value = "/dags/for_rent/my_dag"
        mock_isdir.return_value = False

        # act
        result = DAGMetadataService.list_metadata_table_paths("my_dag", "clean")

        # assert
        assert result == set()

    @mock.patch("bietlejuice.services.dag_metadata_service.os.path.isfile")
    @mock.patch("bietlejuice.services.dag_metadata_service.glob")
    @mock.patch("bietlejuice.services.dag_metadata_service.os.path.isdir")
    @mock.patch.object(DAGPackagesPathService, "get_dag_path")
    def test_primary_path_files_returned_without_extensions(
        self, mock_get_dag_path, mock_isdir, mock_glob, mock_isfile
    ):
        # arrange — primary metadata dir exists with two files; legacy dir absent
        dag_path = "/dags/for_rent/my_dag"
        mock_get_dag_path.return_value = dag_path
        primary_dir = path.join(dag_path, "metadata", "clean")

        def isdir_side_effect(p):
            return p == primary_dir

        mock_isdir.side_effect = isdir_side_effect
        mock_isfile.return_value = True

        primary_files = [
            path.join(primary_dir, "contract.yml"),
            path.join(primary_dir, "nested", "user.yaml"),
        ]

        def glob_side_effect(pattern, recursive=False):
            if primary_dir in pattern:
                return primary_files
            return []

        mock_glob.glob.side_effect = glob_side_effect

        # act
        result = DAGMetadataService.list_metadata_table_paths("my_dag", "clean")

        # assert — extensions stripped; nested path preserved; normpath applied
        assert path.normpath("contract") in result
        assert path.normpath(path.join("nested", "user")) in result
        assert not any(
            name.endswith(".yml") or name.endswith(".yaml") for name in result
        )

    @mock.patch("bietlejuice.services.dag_metadata_service.os.path.isfile")
    @mock.patch("bietlejuice.services.dag_metadata_service.glob")
    @mock.patch("bietlejuice.services.dag_metadata_service.os.path.isdir")
    @mock.patch.object(DAGPackagesPathService, "get_dag_path")
    def test_legacy_path_used_when_primary_absent(
        self, mock_get_dag_path, mock_isdir, mock_glob, mock_isfile
    ):
        # arrange — primary dir absent; legacy dir present with one file
        dag_path = "/dags/for_rent/my_dag"
        mock_get_dag_path.return_value = dag_path

        legacy_dir = mock.patch(
            "bietlejuice.services.dag_metadata_service.DATALAKE_METADATA_PATH",
            "/legacy/metadata",
        )

        with legacy_dir:
            resolved_legacy = path.join("/legacy/metadata", "my_dag", "clean")

            def isdir_side_effect(p):
                return p == resolved_legacy

            mock_isdir.side_effect = isdir_side_effect
            mock_isfile.return_value = True

            def glob_side_effect(pattern, recursive=False):
                if resolved_legacy in pattern:
                    return [path.join(resolved_legacy, "fact_contract.yml")]
                return []

            mock_glob.glob.side_effect = glob_side_effect

            # act
            result = DAGMetadataService.list_metadata_table_paths("my_dag", "clean")

        # assert — file from legacy path is present
        assert path.normpath("fact_contract") in result

    @mock.patch("bietlejuice.services.dag_metadata_service.os.path.isfile")
    @mock.patch("bietlejuice.services.dag_metadata_service.glob")
    @mock.patch("bietlejuice.services.dag_metadata_service.os.path.isdir")
    @mock.patch.object(DAGPackagesPathService, "get_dag_path")
    def test_both_paths_merged_into_union(
        self, mock_get_dag_path, mock_isdir, mock_glob, mock_isfile
    ):
        # arrange — both primary and legacy dirs exist with distinct files
        dag_path = "/dags/for_rent/my_dag"
        mock_get_dag_path.return_value = dag_path
        primary_dir = path.join(dag_path, "metadata", "clean")
        mock_isfile.return_value = True

        with mock.patch(
            "bietlejuice.services.dag_metadata_service.DATALAKE_METADATA_PATH",
            "/legacy/metadata",
        ):
            resolved_legacy = path.join("/legacy/metadata", "my_dag", "clean")

            mock_isdir.return_value = True

            def glob_side_effect(pattern, recursive=False):
                if primary_dir in pattern:
                    return [path.join(primary_dir, "contract.yml")]
                if resolved_legacy in pattern:
                    return [path.join(resolved_legacy, "user.yml")]
                return []

            mock_glob.glob.side_effect = glob_side_effect

            # act
            result = DAGMetadataService.list_metadata_table_paths("my_dag", "clean")

        # assert — union of both paths; no duplicates
        assert path.normpath("contract") in result
        assert path.normpath("user") in result
        assert len(result) == 2
