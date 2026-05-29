"""Unit tests for cluster validation promote script."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[6]
_PROMOTE_SCRIPT = (
    REPO_ROOT
    / "packages/bietlejuice-compiler/scripts/validation/promote_cluster_validation_to_prod.py"
)
_spec = importlib.util.spec_from_file_location(
    "promote_cluster_validation_to_prod", _PROMOTE_SCRIPT
)
_promote_module = importlib.util.module_from_spec(_spec)
assert _spec.loader is not None
sys.modules[_spec.name] = _promote_module
_spec.loader.exec_module(_promote_module)

merge_promoted_cluster = _promote_module.merge_promoted_cluster
promote_cluster_file = _promote_module.promote_cluster_file

CORE_BROKERS_HISTORY_PROD = {
    "type": "databricks_16_4_rfleet_instance_cluster",
    "databricks_conn_id": "databricks_new",
    "access_control_list": {
        "group_name": "analytics-engineers",
        "permission_level": "CAN_MANAGE",
    },
    "custom_configurations": {
        "spark_conf": {
            "spark.sql.shuffle.partitions": "8",
            "spark.databricks.delta.merge.enableLowShuffle": "true",
            "spark.memory.fraction": "0.8",
        }
    },
}

CORE_BROKERS_HISTORY_VALIDATION = {
    "type": "consolidation_s_general_cluster",
    "databricks_conn_id": "databricks_new",
    "access_control_list": {
        "group_name": "analytics-engineers",
        "permission_level": "CAN_MANAGE",
    },
}


class TestMergePromotedCluster:
    def test_preserves_prod_spark_conf(self):
        merged = merge_promoted_cluster(
            CORE_BROKERS_HISTORY_PROD, CORE_BROKERS_HISTORY_VALIDATION
        )
        assert merged["type"] == "consolidation_s_general_cluster"
        assert (
            merged["custom_configurations"]["spark_conf"]
            == (CORE_BROKERS_HISTORY_PROD["custom_configurations"]["spark_conf"])
        )

    def test_type_swap_without_spark_conf(self):
        prod = {
            "type": "databricks_16_4_small_general_fleet_xlarge_single_node",
            "databricks_conn_id": "databricks_new",
        }
        validation = {
            "type": "consolidation_s_general_single_node_cluster",
            "databricks_conn_id": "databricks_new",
        }
        merged = merge_promoted_cluster(prod, validation)
        assert merged == validation

    def test_validation_topology_override_wins_over_prod(self):
        prod = {
            "type": "legacy_cluster",
            "custom_configurations": {
                "num_workers": 1,
                "spark_conf": {"spark.sql.shuffle.partitions": "4"},
            },
        }
        validation = {
            "type": "consolidation_m_general_cluster",
            "custom_configurations": {"num_workers": 3},
        }
        merged = merge_promoted_cluster(prod, validation)
        assert merged["type"] == "consolidation_m_general_cluster"
        assert merged["custom_configurations"]["num_workers"] == 3
        assert merged["custom_configurations"]["spark_conf"] == {
            "spark.sql.shuffle.partitions": "4"
        }

    def test_preserves_prod_top_level_keys_missing_from_validation(self):
        prod = {
            "type": "legacy_cluster",
            "custom_libraries": [{"pypi": {"package": "pandas"}}],
        }
        validation = {"type": "consolidation_s_general_cluster"}
        merged = merge_promoted_cluster(prod, validation)
        assert merged["custom_libraries"] == prod["custom_libraries"]


class TestPromoteClusterFile:
    def test_promotes_and_preserves_spark_conf(self, tmp_path: Path):
        cluster_path = tmp_path / "sample_cluster.yml"
        cluster_path.write_text(
            yaml.dump(
                {
                    "cluster": CORE_BROKERS_HISTORY_PROD,
                    "validation": {"cluster": CORE_BROKERS_HISTORY_VALIDATION},
                },
                default_flow_style=False,
                sort_keys=False,
            ),
            encoding="utf-8",
        )

        assert promote_cluster_file(cluster_path) is True

        document = yaml.safe_load(cluster_path.read_text(encoding="utf-8"))
        assert "validation" not in document
        assert document["cluster"]["type"] == "consolidation_s_general_cluster"
        assert document["cluster"]["custom_configurations"]["spark_conf"]

    def test_skips_file_without_validation_block(self, tmp_path: Path):
        cluster_path = tmp_path / "sample_cluster.yml"
        cluster_path.write_text(
            yaml.dump({"cluster": {"type": "consolidation_s_general_cluster"}}),
            encoding="utf-8",
        )

        assert promote_cluster_file(cluster_path) is False
