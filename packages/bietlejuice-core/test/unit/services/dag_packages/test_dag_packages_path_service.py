from os import path
from unittest import mock
from unittest.mock import Mock

import pytest

from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService


class TestDAGPackagesPathService:
    def setup_method(self):
        DAGPackagesPathService.clear_path_caches()

    def teardown_method(self):
        DAGPackagesPathService.clear_path_caches()

    @mock.patch("bietlejuice.base.service.dag_packages_path_service.scandir")
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.path.isdir")
    def test_find_dag_in_line_folders(
        self, mock_path_isdir, mock_scandir, dag_package_service
    ):
        # arrange
        dag_name = "my_dag"
        dir_mock = Mock()
        dir_mock.name = "path1"
        dir_mock.path = "/path1"
        dir_mock.is_dir.return_value = True
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

    @mock.patch("bietlejuice.base.service.dag_packages_path_service.scandir")
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.path.isdir")
    def test_find_dag_skips_underscore_prefixed_line_folders(
        self, mock_path_isdir, mock_scandir, dag_package_service
    ):
        """Astro bundle dirs must not shadow real domain/DAG packages.

        ``dags/_astro_bundles/journey_optimizer/`` exists as a bundle container.
        Looking up dag ``journey_optimizer`` must resolve
        ``dags/journey_optimizer/journey_optimizer/``, not the bundle folder.
        """
        bundle_domain = Mock()
        bundle_domain.name = "_astro_bundles"
        bundle_domain.path = "/dags/_astro_bundles"
        bundle_domain.is_dir.return_value = True

        real_domain = Mock()
        real_domain.name = "journey_optimizer"
        real_domain.path = "/dags/journey_optimizer"
        real_domain.is_dir.return_value = True

        mock_scandir.return_value = [bundle_domain, real_domain]
        mock_path_isdir.side_effect = lambda candidate: (
            candidate == "/dags/journey_optimizer/journey_optimizer"
        )

        returned_value = dag_package_service._find_dag_in_line_folders(
            "journey_optimizer"
        )

        assert returned_value == "/dags/journey_optimizer/journey_optimizer"
        mock_path_isdir.assert_called_once_with(
            "/dags/journey_optimizer/journey_optimizer"
        )

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
        # arrange — both .yml and .yaml files exist; no manifest so we use glob
        mock_get_dag_path.return_value = "/dags/for_rent/my_dag"
        mock_isdir.return_value = True
        mock_isfile.side_effect = lambda p: ".data_quality_manifest" not in str(p)

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

    @mock.patch(
        "bietlejuice.base.service.dag_packages_path_service.DAGPackagesPathService._manifest_is_fresh"
    )
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.path.isfile")
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.path.isdir")
    @mock.patch.object(DAGPackagesPathService, "get_dag_path")
    def test_list_data_quality_table_paths_reads_manifest_when_present(
        self, mock_get_dag_path, mock_isdir, mock_isfile, mock_manifest_is_fresh
    ):
        mock_get_dag_path.return_value = "/dags/my_dag"
        mock_isdir.return_value = True
        mock_isfile.return_value = True
        mock_manifest_is_fresh.return_value = True
        manifest_content = "table_a\ntable_b\nnested/table_c\n"
        mock_file = mock.mock_open(read_data=manifest_content)
        mock_file.return_value.__iter__ = lambda self: iter(
            manifest_content.splitlines(keepends=True)
        )
        with mock.patch(
            "bietlejuice.base.service.dag_packages_path_service.open", mock_file
        ):
            DAGPackagesPathService.list_data_quality_table_paths_in_composer.cache_clear()
            result = DAGPackagesPathService.list_data_quality_table_paths_in_composer(
                "my_dag", "clean"
            )

        assert "table_a" in result
        assert "table_b" in result
        assert path.normpath("nested/table_c") in result

    @mock.patch(
        "bietlejuice.base.service.dag_packages_path_service.DAGPackagesPathService._manifest_is_fresh"
    )
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.glob")
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.path.isfile")
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.path.isdir")
    @mock.patch.object(DAGPackagesPathService, "get_dag_path")
    def test_list_data_quality_table_paths_ignores_stale_manifest(
        self,
        mock_get_dag_path,
        mock_isdir,
        mock_isfile,
        mock_glob,
        mock_manifest_is_fresh,
    ):
        mock_get_dag_path.return_value = "/dags/my_dag"
        mock_isdir.return_value = True
        mock_isfile.return_value = True
        mock_manifest_is_fresh.return_value = False
        mock_glob.side_effect = lambda pattern, recursive=False: (
            [
                "/dags/my_dag/data_quality/clean/table_a.yml",
                "/dags/my_dag/data_quality/clean/nested/table_b.yaml",
            ]
            if "**/*.yml" in pattern or "**/*.yaml" in pattern
            else []
        )

        DAGPackagesPathService.list_data_quality_table_paths_in_composer.cache_clear()
        result = DAGPackagesPathService.list_data_quality_table_paths_in_composer(
            "my_dag", "clean"
        )

        assert path.normpath("table_a") in result
        assert path.normpath(path.join("nested", "table_b")) in result

    @mock.patch(
        "bietlejuice.base.service.dag_packages_path_service.DAGPackagesPathService._manifest_is_fresh"
    )
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.path.isfile")
    @mock.patch.object(DAGPackagesPathService, "get_dag_path")
    def test_list_queries_files_in_composer_uses_manifest_when_present(
        self, mock_get_dag_path, mock_isfile, mock_manifest_is_fresh
    ):
        mock_get_dag_path.return_value = "/dags/growth/amplitude_subpartitioned"
        mock_isfile.return_value = True
        mock_manifest_is_fresh.return_value = True
        manifest_content = "table_a\ntable_b\ntable_c\n"
        mock_file = mock.mock_open(read_data=manifest_content)
        mock_file.return_value.__iter__ = lambda self: iter(self.readlines())
        with mock.patch(
            "bietlejuice.base.service.dag_packages_path_service.open", mock_file
        ):
            DAGPackagesPathService.list_queries_files_in_composer.cache_clear()
            result = DAGPackagesPathService.list_queries_files_in_composer(
                "amplitude_subpartitioned", "clean"
            )

        assert result == ("table_a", "table_b", "table_c")

    @mock.patch(
        "bietlejuice.base.service.dag_packages_path_service.DAGPackagesPathService._manifest_is_fresh"
    )
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.glob")
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.path.isfile")
    @mock.patch.object(DAGPackagesPathService, "get_dag_path")
    def test_list_queries_files_in_composer_ignores_stale_manifest(
        self, mock_get_dag_path, mock_isfile, mock_glob, mock_manifest_is_fresh
    ):
        mock_get_dag_path.return_value = "/dags/growth/my_dag"
        mock_isfile.return_value = True
        mock_manifest_is_fresh.return_value = False
        mock_glob.return_value = [
            "/dags/growth/my_dag/queries/clean/foo.sql",
            "/dags/growth/my_dag/queries/clean/bar.sql",
        ]

        DAGPackagesPathService.list_queries_files_in_composer.cache_clear()
        result = DAGPackagesPathService.list_queries_files_in_composer(
            "my_dag", "clean"
        )

        assert set(result) == {"bar", "foo"}

    @mock.patch("bietlejuice.base.service.dag_packages_path_service.glob")
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.path.isfile")
    @mock.patch.object(DAGPackagesPathService, "get_dag_path")
    def test_list_queries_files_in_composer_falls_back_to_glob_when_no_manifest(
        self, mock_get_dag_path, mock_isfile, mock_glob
    ):
        mock_get_dag_path.return_value = "/dags/growth/my_dag"
        mock_isfile.return_value = False
        mock_glob.return_value = [
            "/dags/growth/my_dag/queries/clean/foo.sql",
            "/dags/growth/my_dag/queries/clean/bar.sql",
        ]

        result = DAGPackagesPathService.list_queries_files_in_composer(
            "my_dag", "clean"
        )

        assert set(result) == {"bar", "foo"}

    def test_manifest_is_fresh_trusts_deployed_bundle_without_stat(self):
        with (
            mock.patch.dict(
                "os.environ", {"BIETLEJUICE_TRUST_MANIFESTS": "1"}, clear=False
            ),
            mock.patch(
                "bietlejuice.base.service.dag_packages_path_service.path.getmtime"
            ) as mock_getmtime,
        ):
            assert DAGPackagesPathService._manifest_is_fresh(
                "/dags/my_dag/queries/clean/.table_manifest",
                "/dags/my_dag/queries/clean",
            )

        mock_getmtime.assert_not_called()

    def test_manifest_is_fresh_logs_stale_fallback(self, caplog):
        with (
            mock.patch.dict("os.environ", {}, clear=True),
            mock.patch(
                "bietlejuice.base.service.dag_packages_path_service.path.getmtime",
                side_effect=[1.0, 2.0],
            ),
            caplog.at_level(
                "DEBUG",
                logger="bietlejuice.base.service.dag_packages_path_service",
            ),
        ):
            assert not DAGPackagesPathService._manifest_is_fresh(
                "/dags/my_dag/queries/clean/.table_manifest",
                "/dags/my_dag/queries/clean",
            )

        assert "Ignoring stale manifest" in caplog.text

    # --- clear_path_caches tests ---

    @mock.patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser._parse_dag_declaration"
    )
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.scandir")
    @mock.patch.object(DAGPackagesPathService, "_find_dag_in_line_folders")
    def test_clear_path_caches_resets_both_caches(
        self, mock_find, mock_scandir, mock_parse_dag_declaration
    ):
        # arrange — prime both caches
        dir_mock = Mock()
        dir_mock.path = "/dags/for_rent"
        mock_scandir.return_value = [dir_mock]
        mock_find.return_value = "/dags/for_rent/my_dag"
        mock_parse_dag_declaration.cache_clear = Mock()

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
        mock_parse_dag_declaration.cache_clear.assert_called_once()

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

    @mock.patch.object(DAGPackagesPathService, "generate_artifact_file_path")
    def test_resolve_artifact_file_path_checks_all_extensions(
        self, mock_generate, tmp_path
    ):
        base_path = tmp_path / "dags" / "my_dag" / "my_dag_cluster"
        base_path.parent.mkdir(parents=True)
        yaml_path = base_path.with_suffix(".yaml")
        yaml_path.write_text("cluster:\n  type: test\n", encoding="utf-8")
        mock_generate.return_value = str(base_path)

        resolved = DAGPackagesPathService.resolve_artifact_file_path(
            artifact_type="dag_cluster", dag_name="my_dag"
        )

        assert resolved == str(yaml_path)
