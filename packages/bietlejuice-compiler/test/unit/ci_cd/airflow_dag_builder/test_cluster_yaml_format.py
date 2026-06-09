"""Unit tests for cluster YAML dump formatting helpers."""

from __future__ import annotations

import pytest
import yaml

from scripts.ci_cd.airflow_dag_builder.cluster_yaml_format import (
    assert_no_folded_catalog_namespace,
    cluster_file_documents_equal,
    dump_cluster_yaml,
)

_CATALOG_NAMESPACE_KEY = "spark.databricks.sql.initial.catalog.namespace"
_CATALOG_NAMESPACE_VALUE = "quintoandar_{{ var.value.environment }}"


class TestDumpClusterYaml:
    def test_dump_keeps_catalog_namespace_jinja_on_one_line(self):
        document = {
            "cluster": {
                "custom_configurations": {
                    "spark_conf": {_CATALOG_NAMESPACE_KEY: _CATALOG_NAMESPACE_VALUE}
                }
            }
        }
        text = dump_cluster_yaml(document)
        assert _CATALOG_NAMESPACE_VALUE in text
        assert "environment\n        }}" not in text


class TestClusterFileDocumentsEqual:
    def test_ignores_single_vs_double_quote_scalars(self):
        single_quoted = """cluster:
  custom_configurations:
    single_user_name: '{{ var.value.databricks_single_user_name }}'
    spark_conf:
      spark.driver.maxResultSize: '0'
"""
        double_quoted = """cluster:
  custom_configurations:
    single_user_name: "{{ var.value.databricks_single_user_name }}"
    spark_conf:
      spark.driver.maxResultSize: "0"
"""
        assert cluster_file_documents_equal(single_quoted, double_quoted)

    def test_detects_real_content_differences(self):
        left = "cluster:\n  type: consolidation_l_memory_cluster\n"
        right = "cluster:\n  type: consolidation_m_memory_cluster\n"
        assert not cluster_file_documents_equal(left, right)


class TestAssertNoFoldedCatalogNamespace:
    def test_accepts_single_line_jinja(self):
        assert_no_folded_catalog_namespace(
            f"{_CATALOG_NAMESPACE_KEY}: {_CATALOG_NAMESPACE_VALUE}\n"
        )

    def test_rejects_pyyaml_folded_jinja(self):
        folded = yaml.dump(
            {
                "cluster": {
                    "custom_configurations": {
                        "spark_conf": {_CATALOG_NAMESPACE_KEY: _CATALOG_NAMESPACE_VALUE}
                    }
                }
            },
            default_flow_style=False,
            width=80,
        )
        with pytest.raises(ValueError, match="folded spark.databricks"):
            assert_no_folded_catalog_namespace(folded)
