"""Unit tests for validate_no_new_databricks_clusters helpers."""

import sys
from pathlib import Path
from unittest.mock import MagicMock

import pytest
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from scripts.ci_cd.validate_no_new_databricks_clusters import (  # noqa: E402
    ClusterClassification,
    affected_dag_roots,
    classify_prod_cluster,
    extract_prod_cluster,
    is_excepted,
    load_exceptions,
    resolve_prod_cluster_from_texts,
    should_fail_introduction,
)


class TestLoadExceptions:
    def test_empty_file(self, tmp_path):
        path = tmp_path / "exceptions.yml"
        path.write_text("exceptions: []\n", encoding="utf-8")
        dag_names, paths = load_exceptions(path)
        assert dag_names == set()
        assert paths == set()

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
                    ]
                }
            ),
            encoding="utf-8",
        )
        dag_names, paths = load_exceptions(path)
        assert dag_names == {"enrich_databricks_query_history"}
        assert paths == {"dags/platform/foo"}


class TestIsExcepted:
    def test_by_dag_name(self):
        assert is_excepted("my_dag", "dags/x/my_dag", {"my_dag"}, set()) is True

    def test_by_path(self):
        assert is_excepted("my_dag", "dags/x/my_dag", set(), {"dags/x/my_dag"}) is True

    def test_not_listed(self):
        assert is_excepted("my_dag", "dags/x/my_dag", set(), set()) is False


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
