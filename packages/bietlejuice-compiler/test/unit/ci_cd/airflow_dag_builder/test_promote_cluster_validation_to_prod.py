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

    def test_heterogeneous_driver_only_drops_prod_worker(self):
        prod = {
            "type": "custom_cluster",
            "custom_configurations": {
                "node_type_id": "m5a.large",
                "driver_node_type_id": "m5a.xlarge",
                "num_workers": 1,
                "spark_version": "13.3.x-scala2.12",
            },
        }
        validation = {
            "type": "consolidation_xs_general_cluster",
            "custom_configurations": {
                "driver_node_type_id": "m6g.xlarge",
                "num_workers": 1,
                "spark_version": "13.3.x-scala2.12",
            },
        }
        merged = merge_promoted_cluster(prod, validation)
        custom = merged["custom_configurations"]
        assert custom["driver_node_type_id"] == "m6g.xlarge"
        assert "node_type_id" not in custom

    def test_homogeneous_topology_drops_prod_when_validation_omits(self):
        prod = {
            "type": "custom_cluster",
            "custom_configurations": {
                "driver_node_type_id": "m7a.xlarge",
                "node_type_id": "m7a.xlarge",
                "num_workers": 1,
            },
        }
        validation = {
            "type": "consolidation_s_general_cluster",
            "custom_configurations": {"num_workers": 1},
        }
        merged = merge_promoted_cluster(prod, validation)
        custom = merged["custom_configurations"]
        assert custom["num_workers"] == 1
        assert "node_type_id" not in custom
        assert "driver_node_type_id" not in custom

    def test_single_node_promotion_drops_inherited_prod_num_workers(self):
        """ebdb_agent pattern: multi-node prod promoted to single-node validation."""
        prod = {
            "type": "consolidation_xs_memory_cluster",
            "databricks_conn_id": "databricks_new",
            "custom_configurations": {
                "num_workers": 3,
                "driver_node_type_id": "m6g.xlarge",
            },
        }
        validation = {
            "type": "consolidation_m_memory_single_node_cluster",
            "databricks_conn_id": "databricks_new",
            "custom_configurations": {
                "driver_node_type_id": "r7g.2xlarge",
            },
        }
        merged = merge_promoted_cluster(prod, validation)
        custom = merged["custom_configurations"]
        assert merged["type"] == "consolidation_m_memory_single_node_cluster"
        assert custom["driver_node_type_id"] == "r7g.2xlarge"
        assert "num_workers" not in custom

    def test_single_node_promotion_keeps_validation_num_workers(self):
        prod = {
            "type": "consolidation_s_general_cluster",
            "custom_configurations": {"num_workers": 4},
        }
        validation = {
            "type": "consolidation_m_memory_single_node_cluster",
            "custom_configurations": {"num_workers": 0},
        }
        merged = merge_promoted_cluster(prod, validation)
        assert merged["custom_configurations"]["num_workers"] == 0

    def test_validation_explicit_topology_preserved(self):
        prod = {
            "type": "custom_cluster",
            "custom_configurations": {
                "node_type_id": "m5a.large",
                "driver_node_type_id": "m5a.xlarge",
            },
        }
        validation = {
            "type": "consolidation_s_general_cluster",
            "custom_configurations": {
                "node_type_id": "m6g.xlarge",
                "driver_node_type_id": "m6g.xlarge",
            },
        }
        merged = merge_promoted_cluster(prod, validation)
        custom = merged["custom_configurations"]
        assert custom["node_type_id"] == "m6g.xlarge"
        assert custom["driver_node_type_id"] == "m6g.xlarge"

    def test_preserves_validation_aws_attributes_ebs_volume_size(self):
        prod = {
            "type": "databricks_16_4_med_memory_general_cluster",
            "databricks_conn_id": "databricks_new_env",
            "custom_configurations": {
                "single_user_name": "{{ var.value.databricks_single_user_name }}",
                "data_security_mode": "SINGLE_USER",
                "spark_conf": {
                    "spark.databricks.sql.initial.catalog.namespace": (
                        "quintoandar_{{ var.value.environment }}"
                    ),
                },
            },
        }
        validation = {
            "type": "consolidation_s_memory_cluster",
            "databricks_conn_id": "databricks_new_env",
            "custom_configurations": {
                "num_workers": 3,
                "aws_attributes": {"ebs_volume_size": 200},
            },
        }
        merged = merge_promoted_cluster(prod, validation)
        custom = merged["custom_configurations"]
        assert custom["num_workers"] == 3
        assert custom["aws_attributes"]["ebs_volume_size"] == 200
        assert custom["spark_conf"] == prod["custom_configurations"]["spark_conf"]

    def test_validation_init_scripts_survive_promotion(self):
        prod = {
            "type": "custom_cluster_with_sedona",
            "custom_configurations": {
                "node_type_id": "m6g.xlarge",
                "driver_node_type_id": "m6g.xlarge",
                "num_workers": 3,
            },
        }
        validation = {
            "type": "consolidation_s_general_cluster",
            "custom_configurations": {
                "num_workers": 3,
                "init_scripts": [
                    {
                        "s3": {
                            "destination": (
                                "{{ var.value.artifacts_bucket }}/sedona/sedona-init.sh"
                            ),
                            "region": "",
                        }
                    },
                    {
                        "s3": {
                            "destination": (
                                "{{ var.value.artifacts_bucket }}/bi-etl-ejuice/init_script.sh"
                            ),
                            "region": "",
                        }
                    },
                ],
            },
        }

        merged = merge_promoted_cluster(prod, validation)

        custom = merged["custom_configurations"]
        assert (
            custom["init_scripts"]
            == validation["custom_configurations"]["init_scripts"]
        )
        assert "sedona-init.sh" in custom["init_scripts"][0]["s3"]["destination"]


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

    def test_promote_preserves_single_line_spark_conf_jinja(self, tmp_path: Path):
        prod = {
            "type": "databricks_16_4_med_general_cluster",
            "databricks_conn_id": "databricks_new",
            "custom_configurations": {
                "single_user_name": "{{ var.value.databricks_single_user_name }}",
                "data_security_mode": "SINGLE_USER",
                "spark_conf": {
                    "spark.databricks.sql.initial.catalog.namespace": (
                        "quintoandar_{{ var.value.environment }}"
                    ),
                },
            },
        }
        validation = {
            "type": "consolidation_s_general_cluster",
            "databricks_conn_id": "databricks_new",
            "custom_configurations": {"num_workers": 3},
        }
        cluster_path = tmp_path / "enrich_databricks_cluster.yml"
        cluster_path.write_text(
            yaml.dump(
                {"cluster": prod, "validation": {"cluster": validation}},
                default_flow_style=False,
                sort_keys=False,
                width=10_000,
            ),
            encoding="utf-8",
        )

        assert promote_cluster_file(cluster_path) is True

        text = cluster_path.read_text(encoding="utf-8")
        assert "quintoandar_{{ var.value.environment }}" in text
        assert "environment\n        }}" not in text
