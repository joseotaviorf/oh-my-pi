from scripts.dependency_handling.validate_dependency_file_correctness import (
    _ignored_dag_ids,
    compare_dependencies,
)


class TestCompareDependencies:
    def test_no_differences(self):
        deps = {"bietlejuice.a": ["bietlejuice.b:load-clean"]}
        assert compare_dependencies(deps, deps) == {}

    def test_missing_dependency_is_reported(self):
        expected = {"bietlejuice.a": ["bietlejuice.b:load-clean"]}
        existing = {}
        differences = compare_dependencies(expected, existing)
        assert differences == {
            "bietlejuice.a": {"missing": ["bietlejuice.b:load-clean"]}
        }

    def test_ignored_dag_is_skipped_from_missing(self):
        expected = {
            "bietlejuice.enrich_luigijr_x": [
                "bietlejuice.dag_inventory:load-clean-dag"
            ],
            "bietlejuice.other": ["bietlejuice.up:load-clean"],
        }
        existing = {"bietlejuice.other": ["bietlejuice.up:load-clean"]}
        differences = compare_dependencies(
            expected, existing, ignored_dags=frozenset({"bietlejuice.enrich_luigijr_x"})
        )
        assert differences == {}

    def test_ignored_dag_is_skipped_from_extra(self):
        expected = {}
        existing = {"bietlejuice.enrich_luigijr_x": ["bietlejuice.stale:load-clean"]}
        differences = compare_dependencies(
            expected, existing, ignored_dags=frozenset({"bietlejuice.enrich_luigijr_x"})
        )
        assert differences == {}

    def test_non_ignored_dag_still_reported_when_ignore_set_present(self):
        expected = {"bietlejuice.other": ["bietlejuice.up:load-clean"]}
        existing = {}
        differences = compare_dependencies(
            expected, existing, ignored_dags=frozenset({"bietlejuice.enrich_luigijr_x"})
        )
        assert differences == {
            "bietlejuice.other": {"missing": ["bietlejuice.up:load-clean"]}
        }


class TestIgnoredDagIds:
    def test_lists_dag_folders_under_luigijr(self, tmp_path):
        luigijr = tmp_path / "luigijr"
        (luigijr / "enrich_luigijr_a").mkdir(parents=True)
        (luigijr / "gsheets_luigijr_b").mkdir(parents=True)
        (luigijr / "not_a_dir.txt").write_text("x", encoding="utf-8")
        assert _ignored_dag_ids(str(tmp_path)) == frozenset(
            {"bietlejuice.enrich_luigijr_a", "bietlejuice.gsheets_luigijr_b"}
        )

    def test_empty_when_no_ignored_domains(self, tmp_path):
        assert _ignored_dag_ids(str(tmp_path)) == frozenset()

    def test_includes_platform_emr_migration_validation_dags(self, tmp_path):
        platform = tmp_path / "platform"
        (platform / "migration_emr_foo").mkdir(parents=True)
        (platform / "migration_compare_bar").mkdir(parents=True)
        (platform / "dag_runtime_monitoring").mkdir(parents=True)
        assert _ignored_dag_ids(str(tmp_path)) == frozenset(
            {
                "bietlejuice.migration_emr_foo",
                "bietlejuice.migration_compare_bar",
            }
        )
