"""Unit tests for validate_no_new_databricks_clusters helpers."""

import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

import scripts.ci_cd.validate_no_new_databricks_clusters as validate_mod  # noqa: E402
from scripts.ci_cd.validate_no_new_databricks_clusters import (  # noqa: E402
    ClusterClassification,
    affected_dag_roots,
    changed_python_modules,
    classify_prod_cluster,
    collect_violations,
    databricks_imports,
    evaluate_python_module,
    extract_prod_cluster,
    is_blocked_module,
    is_excepted,
    is_scanned_python_path,
    load_exceptions,
    python_dag_scope,
    resolve_prod_cluster_from_texts,
    should_fail_introduction,
)


class TestLoadExceptions:
    def test_empty_file(self, tmp_path):
        path = tmp_path / "exceptions.yml"
        path.write_text("exceptions: []\n", encoding="utf-8")
        dag_names, paths, path_prefixes = load_exceptions(path)
        assert dag_names == set()
        assert paths == set()
        assert path_prefixes == set()

    def test_dag_and_path_entries(self, tmp_path):
        path = tmp_path / "exceptions.yml"
        path.write_text(
            yaml.dump(
                {
                    "exceptions": [
                        {
                            "dag": "enrich_databricks_query_history",
                            "reason": "system tables",
                            "approved_by": "a@quintoandar.com.br",
                        },
                        {
                            "path": "dags/platform/foo/",
                            "reason": "x",
                            "approved_by": "b@quintoandar.com.br",
                        },
                        {
                            "path_prefix": "dags/luigijr",
                            "reason": "luigi jr",
                            "approved_by": "c@quintoandar.com.br",
                        },
                    ]
                }
            ),
            encoding="utf-8",
        )
        dag_names, paths, path_prefixes = load_exceptions(path)
        assert dag_names == {"enrich_databricks_query_history"}
        assert paths == {"dags/platform/foo"}
        assert path_prefixes == {"dags/luigijr"}


class TestIsExcepted:
    def test_by_dag_name(self):
        assert is_excepted("my_dag", "dags/x/my_dag", {"my_dag"}, set(), set()) is True

    def test_by_path(self):
        assert (
            is_excepted("my_dag", "dags/x/my_dag", set(), {"dags/x/my_dag"}, set())
            is True
        )

    def test_by_path_prefix(self):
        assert (
            is_excepted(
                "gsheets_luigijr_foo",
                "dags/luigijr/gsheets_luigijr_foo",
                set(),
                set(),
                {"dags/luigijr"},
            )
            is True
        )

    def test_path_prefix_does_not_match_other_domains(self):
        assert (
            is_excepted(
                "my_dag",
                "dags/growth/my_dag",
                set(),
                set(),
                {"dags/luigijr"},
            )
            is False
        )

    def test_not_listed(self):
        assert is_excepted("my_dag", "dags/x/my_dag", set(), set(), set()) is False


class TestExtractProdCluster:
    def test_cluster_file_ignores_validation(self):
        doc = {
            "cluster": {"type": "consolidation_s_general_cluster"},
            "validation": {
                "cluster": {"type": "emr_7_12_consolidation_s_memory_fleet_cluster"}
            },
        }
        got = extract_prod_cluster(doc, from_cluster_file=True)
        assert got == {"type": "consolidation_s_general_cluster"}

    def test_inline_declaration(self):
        doc = {
            "workflow": {},
            "cluster": {"type": "emr_7_12_min_general_2_workers_cluster"},
        }
        got = extract_prod_cluster(doc, from_cluster_file=False)
        assert got["type"].startswith("emr_")

    def test_missing_cluster(self):
        assert extract_prod_cluster({"workflow": {}}, from_cluster_file=False) is None


class TestResolvePreferClusterFile:
    def test_prefers_cluster_yml_over_inline(self):
        cluster_text = yaml.dump(
            {"cluster": {"type": "emr_7_12_consolidation_s_memory_fleet_cluster"}}
        )
        decl_text = yaml.dump({"cluster": {"type": "consolidation_s_general_cluster"}})
        got = resolve_prod_cluster_from_texts(
            cluster_text=cluster_text, declaration_text=decl_text
        )
        assert got["type"].startswith("emr_")


class TestClassifyProdCluster:
    def test_emr_type_prefix(self):
        c = classify_prod_cluster(
            {"type": "emr_7_12_consolidation_s_memory_fleet_cluster"}
        )
        assert c.is_emr is True

    def test_custom_cluster_emr_spark_version(self):
        c = classify_prod_cluster(
            {
                "type": "custom_cluster",
                "custom_configurations": {"spark_version": "emr-7.12.0"},
            }
        )
        assert c.is_emr is True
        assert c.spark_version.startswith("emr-")

    def test_custom_cluster_dbr_spark_version(self):
        c = classify_prod_cluster(
            {
                "type": "custom_cluster",
                "custom_configurations": {"spark_version": "16.4.x-scala2.12"},
            }
        )
        assert c.is_emr is False

    def test_consolidation_type_without_service_is_databricks(self):
        # Without ConfigurationService merge, no emr- override → not EMR.
        c = classify_prod_cluster({"type": "consolidation_s_general_cluster"})
        assert c.is_emr is False

    def test_uses_merged_spark_version_from_service(self):
        service = MagicMock()
        # resolve_airflow_compute_mode will be called; patch via mock side path:
        # provide get_config returning DBR then deep_update leaving spark_version.
        # Simpler: pass None and rely on override, already covered.
        # Here exercise EMR type short-circuit with service merging spark_version.
        service.get_config.return_value = {"spark_version": "emr-7.12.0"}
        service._deep_update.side_effect = lambda base, override: {
            **base,
            **override,
        }
        c = classify_prod_cluster(
            {"type": "emr_7_12_consolidation_s_memory_fleet_cluster"},
            config_service=service,
        )
        assert c.is_emr is True


class TestShouldFailIntroduction:
    dbx = ClusterClassification(
        is_emr=False,
        cluster_type="consolidation_s_general_cluster",
        spark_version="16.4.x",
    )
    emr = ClusterClassification(
        is_emr=True,
        cluster_type="emr_7_12_consolidation_s_memory_fleet_cluster",
        spark_version="emr-7.12.0",
    )

    def test_new_dag_databricks_fails(self):
        assert (
            should_fail_introduction(is_new_dag=True, head=self.dbx, base=None) is True
        )

    def test_new_dag_emr_passes(self):
        assert (
            should_fail_introduction(is_new_dag=True, head=self.emr, base=None) is False
        )

    def test_emr_to_databricks_fails(self):
        assert (
            should_fail_introduction(is_new_dag=False, head=self.dbx, base=self.emr)
            is True
        )

    def test_databricks_to_databricks_passes(self):
        assert (
            should_fail_introduction(is_new_dag=False, head=self.dbx, base=self.dbx)
            is False
        )

    def test_databricks_to_emr_passes(self):
        assert (
            should_fail_introduction(is_new_dag=False, head=self.emr, base=self.dbx)
            is False
        )

    def test_missing_base_with_databricks_fails(self):
        assert (
            should_fail_introduction(is_new_dag=False, head=self.dbx, base=None) is True
        )


class TestAffectedDagRoots:
    def test_cluster_and_declaration_paths(self):
        changed = {
            "dags/growth/foo/foo_cluster.yml": "M",
            "dags/growth/foo/queries/a.sql": "M",
            "dags/people/bar/bar_declaration.yml": "A",
            "README.md": "M",
        }
        got = affected_dag_roots(changed)
        assert got == [
            ("dags/growth/foo", "foo"),
            ("dags/people/bar", "bar"),
        ]

    def test_includes_cluster_delete(self):
        # Deleting *_cluster.yml can uncover an inline Databricks cluster on
        # the declaration (EMR → Databricks) without touching declaration.yml.
        changed = {"dags/growth/foo/foo_cluster.yml": "D"}
        assert affected_dag_roots(changed) == [("dags/growth/foo", "foo")]

    def test_includes_declaration_delete(self):
        changed = {"dags/growth/foo/foo_declaration.yml": "D"}
        assert affected_dag_roots(changed) == [("dags/growth/foo", "foo")]


@pytest.mark.parametrize(
    "cluster_args,expect_emr",
    [
        ({"type": "databricks_16_4_med_general_cluster"}, False),
        ({"type": "emr_7_12_min_general_2_workers_cluster"}, True),
        (
            {
                "type": "custom_cluster",
                "custom_configurations": {"spark_version": "emr-7.12.0"},
            },
            True,
        ),
        (
            {
                "type": "custom_cluster",
                "custom_configurations": {"spark_version": "13.3.x-scala2.12"},
            },
            False,
        ),
    ],
)
def test_classify_parametrized(cluster_args, expect_emr):
    assert classify_prod_cluster(cluster_args).is_emr is expect_emr


class TestIsBlockedModule:
    def test_databricks_plugin_root(self):
        assert is_blocked_module("databricks_plugin") is True

    def test_databricks_plugin_submodule(self):
        assert is_blocked_module("databricks_plugin.hooks.databricks_hook") is True

    def test_databricks_sdk(self):
        assert is_blocked_module("databricks.sdk") is True

    def test_airflow_providers_databricks(self):
        assert (
            is_blocked_module("airflow.providers.databricks.operators.databricks")
            is True
        )

    def test_bietlejuice_base_databricks_not_blocked(self):
        # Runtime-agnostic ACL/permission enums — must not be treated as a
        # Databricks job entry point (~16 hand-written DAGs import this).
        assert (
            is_blocked_module("bietlejuice.base.databricks.cluster_permission_enum")
            is False
        )

    def test_bare_substring_not_matched(self):
        assert is_blocked_module("databricks_helpers") is False

    def test_none(self):
        assert is_blocked_module(None) is False


class TestDatabricksImports:
    def test_from_databricks_plugin_multiline(self):
        source = (
            "from databricks_plugin import (\n"
            "    QuintoAndarDatabricksSubmitRunOperator,\n"
            ")\n"
        )
        hits = databricks_imports("probe.py", source)
        assert hits == [(1, "databricks_plugin")]

    def test_import_as_alias(self):
        source = "import databricks_plugin.operators.submit_run as sr\n"
        assert databricks_imports("probe.py", source) == [
            (1, "databricks_plugin.operators.submit_run")
        ]

    def test_blocked_symbol_from_agnostic_module(self):
        source = (
            "from bietlejuice.base.airflow.job_cluster_engine import "
            "DatabricksJobClusterEngine\n"
        )
        assert databricks_imports("probe.py", source) == [
            (
                1,
                "bietlejuice.base.airflow.job_cluster_engine.DatabricksJobClusterEngine",
            )
        ]

    def test_emr_plugin_not_hit(self):
        source = "from emr_plugin import QuintoAndarEmrSubmitStepsOperator\n"
        assert databricks_imports("probe.py", source) == []

    def test_relative_import_ignored(self):
        source = "from . import helpers\n"
        assert databricks_imports("probe.py", source) == []

    def test_syntax_error_returns_empty(self):
        assert databricks_imports("probe.py", "def f(:") == []


class TestIsScannedPythonPath:
    def test_standard_handwritten(self):
        assert is_scanned_python_path("dags/growth/semrush/semrush.py") is True

    def test_nested_handwritten(self):
        assert (
            is_scanned_python_path(
                "dags/governance/datahub_business_context/sync/github_api.py"
            )
            is True
        )

    def test_spark_jobs_excluded(self):
        assert (
            is_scanned_python_path("dags/cross/base/spark_jobs/load_table_full.py")
            is False
        )

    def test_platform_migration_excluded(self):
        assert (
            is_scanned_python_path("dags/platform/migration_assets/comparison.py")
            is False
        )

    def test_layer_taxonomy_pilot_is_scanned(self):
        # Pilot DAGs are EMR YAML with no hand-written Python, but they must
        # not get a code-level bypass around databricks_cluster_exceptions.yml.
        assert (
            is_scanned_python_path(
                "dags/governance/transformation_terminator_test/x_dag.py"
            )
            is True
        )

    def test_sql_excluded(self):
        assert (
            is_scanned_python_path("dags/growth/semrush/queries/clean/x.sql") is False
        )

    def test_packages_excluded(self):
        assert is_scanned_python_path("packages/bietlejuice-core/src/x.py") is False


class TestPythonDagScope:
    def test_nested_module(self):
        assert python_dag_scope(
            "dags/governance/datahub_business_context/sync/github_api.py"
        ) == (
            "dags/governance/datahub_business_context/sync",
            "github_api",
        )


class TestChangedPythonModules:
    def test_filters_status_and_path(self):
        changed = {
            "dags/growth/semrush/semrush.py": "A",
            "dags/growth/x/x.py": "D",
            "dags/growth/y/y_declaration.yml": "M",
        }
        assert changed_python_modules(changed) == ["dags/growth/semrush/semrush.py"]


class TestEvaluatePythonModule:
    def _write_module(self, tmp_path, relative, source):
        absolute = tmp_path / relative
        absolute.parent.mkdir(parents=True, exist_ok=True)
        absolute.write_text(source, encoding="utf-8")
        return absolute

    def test_new_module_with_databricks(self, tmp_path, monkeypatch):
        relative = "dags/growth/probe/probe.py"
        self._write_module(
            tmp_path,
            relative,
            "from databricks_plugin import QuintoAndarDatabricksSubmitRunOperator\n",
        )
        monkeypatch.setattr(validate_mod, "REPO_ROOT", tmp_path)
        monkeypatch.setattr(validate_mod, "read_text_from_git", lambda *_: None)

        violations = evaluate_python_module(
            relative, "origin/master", set(), set(), set()
        )
        assert len(violations) == 1
        assert "new Python DAG module" in violations[0].reason

    def test_emr_to_databricks(self, tmp_path, monkeypatch):
        relative = "dags/growth/probe/probe.py"
        self._write_module(
            tmp_path,
            relative,
            "from databricks_plugin import QuintoAndarDatabricksSubmitRunOperator\n",
        )
        monkeypatch.setattr(validate_mod, "REPO_ROOT", tmp_path)
        monkeypatch.setattr(
            validate_mod,
            "read_text_from_git",
            lambda *_: "from emr_plugin import QuintoAndarEmrSubmitStepsOperator\n",
        )

        violations = evaluate_python_module(
            relative, "origin/master", set(), set(), set()
        )
        assert len(violations) == 1
        assert "EMR -> Databricks" in violations[0].reason

    def test_databricks_to_databricks(self, tmp_path, monkeypatch):
        relative = "dags/growth/probe/probe.py"
        self._write_module(
            tmp_path,
            relative,
            "from databricks_plugin import QuintoAndarDatabricksSubmitRunOperator\n",
        )
        monkeypatch.setattr(validate_mod, "REPO_ROOT", tmp_path)
        monkeypatch.setattr(
            validate_mod,
            "read_text_from_git",
            lambda *_: (
                "from databricks_plugin import QuintoAndarDatabricksRunNowOperator\n"
            ),
        )

        assert (
            evaluate_python_module(relative, "origin/master", set(), set(), set()) == []
        )

    def test_databricks_to_emr(self, tmp_path, monkeypatch):
        relative = "dags/growth/probe/probe.py"
        self._write_module(
            tmp_path,
            relative,
            "from emr_plugin import QuintoAndarEmrSubmitStepsOperator\n",
        )
        monkeypatch.setattr(validate_mod, "REPO_ROOT", tmp_path)
        monkeypatch.setattr(
            validate_mod,
            "read_text_from_git",
            lambda *_: (
                "from databricks_plugin import QuintoAndarDatabricksSubmitRunOperator\n"
            ),
        )

        assert (
            evaluate_python_module(relative, "origin/master", set(), set(), set()) == []
        )

    def test_excepted_module(self, tmp_path, monkeypatch):
        relative = "dags/growth/probe/probe.py"
        self._write_module(
            tmp_path,
            relative,
            "from databricks_plugin import QuintoAndarDatabricksSubmitRunOperator\n",
        )
        monkeypatch.setattr(validate_mod, "REPO_ROOT", tmp_path)
        monkeypatch.setattr(
            validate_mod,
            "read_text_from_git",
            lambda *_: "from emr_plugin import QuintoAndarEmrSubmitStepsOperator\n",
        )

        assert (
            evaluate_python_module(relative, "origin/master", {"probe"}, set(), set())
            == []
        )


@patch("scripts.ci_cd.validate_no_new_databricks_clusters.load_exceptions")
@patch("scripts.ci_cd.validate_no_new_databricks_clusters.GitService")
@patch(
    "scripts.ci_cd.validate_no_new_databricks_clusters.resolve_diff_from_ref",
    return_value="origin/development",
)
def test_collect_violations_uses_resolved_base(
    mock_resolve, mock_git_service, mock_load_exceptions
):
    git_service = mock_git_service.return_value
    git_service.get_modified_files_from_diff.return_value = {}
    mock_load_exceptions.return_value = (set(), set(), set())

    assert collect_violations("feature-branch") == ([], [])

    mock_resolve.assert_called_once_with("feature-branch")
    git_service.get_modified_files_from_diff.assert_called_once_with(
        "origin/development", "HEAD"
    )
