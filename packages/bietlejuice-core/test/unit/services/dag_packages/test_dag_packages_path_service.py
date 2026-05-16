from os import path
from unittest import mock
from unittest.mock import Mock

import pytest

from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService


class TestDAGPackagesPathService:
    def setup_method(self):
        DAGPackagesPathService._line_folders_cache = None
        DAGPackagesPathService.get_dag_path.cache_clear()

    def teardown_method(self):
        DAGPackagesPathService._line_folders_cache = None
        DAGPackagesPathService.get_dag_path.cache_clear()

    @mock.patch("bietlejuice.base.service.dag_packages_path_service.scandir")
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.path.isdir")
    def test_find_dag_in_line_folders(
        self, mock_path_isdir, mock_scandir, dag_package_service
    ):
        # arrange
        dag_name = "my_dag"
        dir_mock = Mock()
        dir_mock.path = "/path1"
        mock_scandir.return_value = [dir_mock]
        mock_path_isdir.return_value = True
        expected_value = "/path1/my_dag"

        # act
        returned_value = dag_package_service._find_dag_in_line_folders(dag_name)

        # assert
        assert returned_value == expected_value

    @mock.patch("bietlejuice.base.service.dag_packages_path_service.scandir")
    def test_find_dag_in_line_folders_for_non_existent_ones(
        self, mock_scandir, dag_package_service
    ):
        # arrange - scandir returns no directories, so no DAG is found
        dag_name = "my_dag"
        mock_scandir.return_value = []
        expected_value = None

        # act
        returned_value = dag_package_service._find_dag_in_line_folders(dag_name)

        # assert
        assert returned_value == expected_value

    @pytest.mark.parametrize(
        "dag_name, is_migrated_mock, expected_return",
        [("dag1", True, "new/path/mocked")],
    )
    @mock.patch.object(DAGPackagesPathService, "_find_dag_in_line_folders")
    def test_get_dag_parent_path(
        self,
        mock_find_dag_in_line_folders,
        dag_name,
        is_migrated_mock,
        expected_return,
        dag_package_service,
    ):
        # arrange
        if is_migrated_mock:
            mock_find_dag_in_line_folders.return_value = f"new/path/mocked/{dag_name}"
        else:
            mock_find_dag_in_line_folders.return_value = False
        # act
        returned_value = dag_package_service.get_dag_parent_path(dag_name)

        # assert
        assert returned_value == expected_return

    @pytest.mark.parametrize(
        "dag_name, dag_path, expected_return",
        [("dag1", "new/path/mocked", "new/path/mocked")],
    )
    @mock.patch.object(DAGPackagesPathService, "_find_dag_in_line_folders")
    def test_get_dag_path(
        self,
        mock_find_dag_in_line_folders,
        dag_name,
        dag_path,
        expected_return,
        dag_package_service,
    ):
        # arrange
        DAGPackagesPathService.get_dag_path.cache_clear()  # Ensure test isolation
        mock_find_dag_in_line_folders.return_value = dag_path

        # act
        returned_value = dag_package_service.get_dag_path(dag_name)

        # assert
        assert returned_value == expected_return

    @pytest.mark.parametrize(
        "artifact_type, dag_name, layer, expected_return",
        [
            ("query", "dag1", "clean", ["new/path/mocked/dag1/queries/clean/tb1.sql"]),
            (
                "metadata",
                "dag1",
                "clean",
                ["new/path/mocked/dag1/metadata/clean/tb1.yml"],
            ),
        ],
    )
    @mock.patch.object(
        DAGPackagesPathService, "_find_dag_in_line_folders", return_value=None
    )
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.glob")
    def test_list_artifact_file_paths(
        self,
        mock_glob,
        _mock_find,
        artifact_type,
        dag_name,
        layer,
        expected_return,
        dag_package_service,
    ):
        # arrange
        mock_glob.return_value = [
            "new/path/mocked/dag1/queries/clean/tb1.sql",
            "new/path/mocked/dag1/metadata/clean/tb1.yml",
        ]

        # act
        returned_value = dag_package_service.list_artifact_file_paths(
            artifact_type, dag_name, layer
        )

        # assert
        assert returned_value == expected_return
        mock_glob.assert_called_once_with(
            pathname=dag_package_service.generate_artifact_file_path(
                artifact_type, dag_name, layer, table_name="**", add_default_ext=False
            ),
            recursive=True,
        )

    # --- _line_folders_cache tests ---

    @mock.patch("bietlejuice.base.service.dag_packages_path_service.scandir")
    def test_get_line_folders_calls_scandir_once(self, mock_scandir):
        # arrange
        dir_mock = Mock()
        dir_mock.path = "/dags/for_rent"
        mock_scandir.return_value = [dir_mock]

        # act — call twice
        DAGPackagesPathService._get_line_folders()
        DAGPackagesPathService._get_line_folders()

        # assert — filesystem scanned only once; second call uses cached list
        mock_scandir.assert_called_once()

    @mock.patch("bietlejuice.base.service.dag_packages_path_service.scandir")
    def test_get_line_folders_cache_reset_allows_rescan(self, mock_scandir):
        # arrange
        dir_mock = Mock()
        dir_mock.path = "/dags/for_rent"
        mock_scandir.return_value = [dir_mock]

        # act — prime the cache, reset it, then call again
        DAGPackagesPathService._get_line_folders()
        DAGPackagesPathService._line_folders_cache = None
        DAGPackagesPathService._get_line_folders()

        # assert — scandir called twice because the cache was cleared between calls
        assert mock_scandir.call_count == 2

    # --- get_dag_path @lru_cache tests ---

    @mock.patch.object(DAGPackagesPathService, "_find_dag_in_line_folders")
    def test_get_dag_path_lru_caches_result(self, mock_find):
        # arrange
        mock_find.return_value = "/dags/for_rent/my_dag"

        # act — call twice with the same argument
        result_1 = DAGPackagesPathService.get_dag_path("my_dag")
        result_2 = DAGPackagesPathService.get_dag_path("my_dag")

        # assert — same result returned; underlying lookup performed only once
        assert result_1 == result_2 == "/dags/for_rent/my_dag"
        mock_find.assert_called_once()

    @mock.patch.object(DAGPackagesPathService, "_find_dag_in_line_folders")
    def test_get_dag_path_cache_clear_forces_fresh_lookup(self, mock_find):
        # arrange
        mock_find.return_value = "/dags/for_rent/my_dag"

        # act — prime the cache, clear it, then call again
        DAGPackagesPathService.get_dag_path("my_dag")
        DAGPackagesPathService.get_dag_path.cache_clear()
        DAGPackagesPathService.get_dag_path("my_dag")

        # assert — lookup function called twice because the LRU cache was cleared
        assert mock_find.call_count == 2

    # --- list_data_quality_table_paths_in_composer tests ---

    @mock.patch("bietlejuice.base.service.dag_packages_path_service.path.isdir")
    @mock.patch.object(DAGPackagesPathService, "get_dag_path")
    def test_list_data_quality_table_paths_empty_when_dir_absent(
        self, mock_get_dag_path, mock_isdir
    ):
        # arrange — data_quality folder does not exist
        mock_get_dag_path.return_value = "/dags/for_rent/my_dag"
        mock_isdir.return_value = False

        # act
        result = DAGPackagesPathService.list_data_quality_table_paths_in_composer(
            "my_dag", "clean"
        )

        # assert
        assert result == set()

    @mock.patch("bietlejuice.base.service.dag_packages_path_service.path.isfile")
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.path.isdir")
    @mock.patch(
        "bietlejuice.base.service.dag_packages_path_service.glob",
        side_effect=lambda pattern, recursive=False: (
            [
                "/dags/for_rent/my_dag/data_quality/clean/table_a.yml",
                "/dags/for_rent/my_dag/data_quality/clean/nested/table_b.yaml",
            ]
            if "**/*.yml" in pattern or "**/*.yaml" in pattern
            else []
        ),
    )
    @mock.patch.object(DAGPackagesPathService, "get_dag_path")
    def test_list_data_quality_table_paths_strips_extensions(
        self, mock_get_dag_path, mock_glob, mock_isdir, mock_isfile
    ):
        # arrange — both .yml and .yaml files exist
        mock_get_dag_path.return_value = "/dags/for_rent/my_dag"
        mock_isdir.return_value = True
        mock_isfile.return_value = True

        # act
        result = DAGPackagesPathService.list_data_quality_table_paths_in_composer(
            "my_dag", "clean"
        )

        # assert — extensions stripped; nested path preserved; normpath applied
        assert path.normpath("table_a") in result
        assert path.normpath(path.join("nested", "table_b")) in result
        assert not any(
            name.endswith(".yml") or name.endswith(".yaml") for name in result
        )

    # --- clear_path_caches tests ---

    @mock.patch("bietlejuice.base.service.dag_packages_path_service.scandir")
    @mock.patch.object(DAGPackagesPathService, "_find_dag_in_line_folders")
    def test_clear_path_caches_resets_both_caches(self, mock_find, mock_scandir):
        # arrange — prime both caches
        dir_mock = Mock()
        dir_mock.path = "/dags/for_rent"
        mock_scandir.return_value = [dir_mock]
        mock_find.return_value = "/dags/for_rent/my_dag"

        DAGPackagesPathService._get_line_folders()
        DAGPackagesPathService.get_dag_path("my_dag")

        # act — clear both in one call
        DAGPackagesPathService.clear_path_caches()

        # trigger both caches again
        DAGPackagesPathService._get_line_folders()
        DAGPackagesPathService.get_dag_path("my_dag")

        # assert — each underlying call was made twice (prime + post-clear)
        assert mock_scandir.call_count == 2
        assert mock_find.call_count == 2

    # NOTE: tests for get_query_file_content_in_spark_jobs that depend on
    # bietlejuice.base.spark.runtime_detector live in
    # packages/bietlejuice-runtime/test/unit/services/test_dag_packages_path_service_emr.py
    # because the runtime_detector module is shipped by bietlejuice-runtime.

    @mock.patch("bietlejuice.base.service.dag_packages_path_service.scandir")
    @mock.patch.object(DAGPackagesPathService, "_find_dag_in_line_folders")
    def test_clear_path_caches_is_idempotent(self, mock_find, mock_scandir):
        # arrange — call clear on already-empty caches (should not raise)
        mock_scandir.return_value = []
        mock_find.return_value = "/dags/for_rent/my_dag"

        # act / assert — two consecutive clears without error
        DAGPackagesPathService.clear_path_caches()
        DAGPackagesPathService.clear_path_caches()

    # --- Volume (Databricks) fallback in _get_line_folders ---

    @mock.patch(
        "bietlejuice.base.service.dag_packages_path_service.DAG_PACKAGES_ROOT", None
    )
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.path.isdir")
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.scandir")
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.HierarchicalConf")
    def test_get_line_folders_uses_volume_when_dag_packages_root_is_none(
        self, mock_conf_cls, mock_scandir, mock_isdir
    ):
        # arrange — simulate Databricks: no DAG_PACKAGES_ROOT, but a mounted Volume
        volume = "/Volumes/prod/bi"
        prefix = "github-repos/bi-etl-ejuice/"
        expected_dags_root = path.join(volume, prefix, "dags")

        mock_conf_instance = mock_conf_cls.return_value
        mock_conf_instance.get_config.side_effect = lambda k: (
            volume if k == "volume_databricks_bucket" else prefix
        )
        mock_isdir.return_value = True

        dir_mock = Mock()
        dir_mock.name = "people"
        dir_mock.path = path.join(expected_dags_root, "people")
        mock_scandir.return_value = [dir_mock]

        # act
        result = DAGPackagesPathService._get_line_folders()

        # assert — scandir was called on the Volume dags/ root
        mock_scandir.assert_called_once_with(expected_dags_root)
        assert result == [dir_mock]

    @mock.patch(
        "bietlejuice.base.service.dag_packages_path_service.DAG_PACKAGES_ROOT", None
    )
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.path.isdir")
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.HierarchicalConf")
    def test_get_line_folders_returns_empty_when_volume_dags_dir_absent(
        self, mock_conf_cls, mock_isdir
    ):
        # arrange — Volume config resolves but the dags/ directory does not exist
        mock_conf_instance = mock_conf_cls.return_value
        mock_conf_instance.get_config.side_effect = lambda k: (
            "/vol" if k == "volume_databricks_bucket" else "prefix/"
        )
        mock_isdir.return_value = False

        # act
        result = DAGPackagesPathService._get_line_folders()

        # assert — graceful fallback to empty list
        assert result == []

    @mock.patch(
        "bietlejuice.base.service.dag_packages_path_service.DAG_PACKAGES_ROOT", None
    )
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.HierarchicalConf")
    def test_get_line_folders_returns_empty_on_config_error(self, mock_conf_cls):
        # arrange — HierarchicalConf raises (e.g. missing key outside Databricks)
        mock_conf_cls.side_effect = Exception("config unavailable")

        # act
        result = DAGPackagesPathService._get_line_folders()

        # assert — exception swallowed; empty list returned
        assert result == []

    @mock.patch(
        "bietlejuice.base.service.dag_packages_path_service.DAG_PACKAGES_ROOT", None
    )
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.path.isdir")
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.scandir")
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.HierarchicalConf")
    def test_get_dag_path_resolves_via_volume(
        self, mock_conf_cls, mock_scandir, mock_isdir
    ):
        # arrange — Volume exposes dags/people/oitchau_api/
        volume = "/Volumes/prod/bi"
        prefix = "github-repos/bi-etl-ejuice/"
        dags_root = path.join(volume, prefix, "dags")

        mock_conf_instance = mock_conf_cls.return_value
        mock_conf_instance.get_config.side_effect = lambda k: (
            volume if k == "volume_databricks_bucket" else prefix
        )
        mock_isdir.side_effect = lambda p: (
            p
            in {
                dags_root,
                path.join(dags_root, "people", "oitchau_api"),
            }
        )

        people_entry = Mock()
        people_entry.name = "people"
        people_entry.path = path.join(dags_root, "people")
        mock_scandir.return_value = [people_entry]

        # act
        result = DAGPackagesPathService.get_dag_path("oitchau_api")

        # assert — resolved to the Volume-mounted path
        assert result == path.join(dags_root, "people", "oitchau_api")
