from bietlejuice.base.dependencies.ignored_dag_ids import (
    filter_ignored_dag_dependencies,
    ignored_dag_ids,
)


class TestIgnoredDagIds:
    def test_lists_dag_folders_under_luigijr(self, tmp_path):
        luigijr = tmp_path / "luigijr"
        (luigijr / "enrich_luigijr_a").mkdir(parents=True)
        (luigijr / "gsheets_luigijr_b").mkdir(parents=True)
        (luigijr / "not_a_dir.txt").write_text("x", encoding="utf-8")
        assert ignored_dag_ids(str(tmp_path)) == frozenset(
            {"bietlejuice.enrich_luigijr_a", "bietlejuice.gsheets_luigijr_b"}
        )

    def test_empty_when_no_ignored_domains(self, tmp_path):
        assert ignored_dag_ids(str(tmp_path)) == frozenset()

    def test_includes_platform_emr_migration_validation_dags(self, tmp_path):
        platform = tmp_path / "platform"
        (platform / "migration_emr_foo").mkdir(parents=True)
        (platform / "migration_compare_bar").mkdir(parents=True)
        (platform / "dag_runtime_monitoring").mkdir(parents=True)
        assert ignored_dag_ids(str(tmp_path)) == frozenset(
            {
                "bietlejuice.migration_emr_foo",
                "bietlejuice.migration_compare_bar",
            }
        )

    def test_includes_layer_taxonomy_pilot_dags_only(self, tmp_path):
        """Other DAGs under dags/governance/ are real pipelines and must stay tracked."""
        # arrange
        governance = tmp_path / "governance"
        (governance / "transformation_terminator_test").mkdir(parents=True)
        (governance / "consumption_offboarding_test").mkdir(parents=True)
        (governance / "glue_table_version_cleanup").mkdir(parents=True)

        # act / assert
        assert ignored_dag_ids(str(tmp_path)) == frozenset(
            {
                "bietlejuice.transformation_terminator_test",
                "bietlejuice.consumption_offboarding_test",
            }
        )


class TestFilterIgnoredDagDependencies:
    def test_removes_ignored_dag_keys(self, tmp_path, monkeypatch):
        platform = tmp_path / "platform"
        (platform / "migration_emr_foo").mkdir(parents=True)
        monkeypatch.setattr(
            "bietlejuice.base.dependencies.ignored_dag_ids.DAG_PACKAGES_ROOT",
            str(tmp_path),
        )

        dependencies = {
            "bietlejuice.migration_emr_foo": [
                "bietlejuice.up:load-clean:first-run-of-day"
            ],
            "bietlejuice.enrich_velo": ["bietlejuice.dw:load-dw:first-run-of-day"],
        }

        assert filter_ignored_dag_dependencies(dependencies) == {
            "bietlejuice.enrich_velo": ["bietlejuice.dw:load-dw:first-run-of-day"],
        }
