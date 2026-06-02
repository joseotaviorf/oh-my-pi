"""Unit tests for cluster YAML dump formatting helpers."""

from __future__ import annotations

import pytest
import yaml

from scripts.ci_cd.airflow_dag_builder.cluster_yaml_format import (
    assert_no_folded_catalog_namespace,
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
