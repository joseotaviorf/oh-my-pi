"""Unit tests for migrate_consolidation_to_gen7 and gen7 topology bump helpers."""

from __future__ import annotations

from pathlib import Path

import yaml

from bietlejuice.services.configuration_service import ConfigurationService
from scripts.ci_cd.airflow_dag_builder.cluster_validation_mapping import (
    bump_cluster_topology_to_gen7,
    bump_instance_type_for_role,
    is_consolidation_cluster_type,
)
from scripts.validation.migrate_consolidation_to_gen7 import migrate_cluster_file

pytest_plugins = [
    "test.unit.ci_cd.airflow_dag_builder.cluster_validation_prod_env",
]


class TestBumpInstanceTypeForRole:
    def test_worker_preserves_nvme(self):
        assert (
            bump_instance_type_for_role(
                "m6gd.4xlarge", role="worker", single_node=False
            )
            == "m7gd.4xlarge"
        )

    def test_driver_strips_nvme(self):
        assert (
            bump_instance_type_for_role("m6gd.xlarge", role="driver", single_node=False)
            == "m7g.xlarge"
        )

    def test_single_node_preserves_nvme(self):
        assert (
            bump_instance_type_for_role("m6gd.2xlarge", role="driver", single_node=True)
            == "m7gd.2xlarge"
        )


class TestBumpClusterTopologyToGen7:
    def test_single_node_skips_driver_nvme_strip(self, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "prod")
        ConfigurationService._instance_cache.clear()

        cluster = {
            "type": "consolidation_s_general_single_node_cluster",
            "custom_configurations": {
                "driver_node_type_id": "m6gd.2xlarge",
                "num_workers": 0,
            },
        }
        bumped = bump_cluster_topology_to_gen7(cluster)
        custom = bumped["custom_configurations"]
        assert custom["driver_node_type_id"] == "m7gd.2xlarge"


class TestIsConsolidationClusterType:
    def test_consolidation_prefix(self):
        assert is_consolidation_cluster_type("consolidation_s_general_cluster")
        assert is_consolidation_cluster_type("wonka_consolidation_s_general_cluster")
        assert not is_consolidation_cluster_type("databricks_16_4_med_general_cluster")


class TestMigrateClusterFile:
    def test_bump_only_without_validation(self, tmp_path: Path, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "prod")
        ConfigurationService._instance_cache.clear()
        config_service = ConfigurationService()

        cluster_path = tmp_path / "dw_listing_cluster.yml"
        cluster_path.write_text(
            yaml.safe_dump(
                {
                    "cluster": {
                        "type": "consolidation_s_general_cluster",
                        "custom_configurations": {
                            "driver_node_type_id": "m6gd.xlarge",
                            "node_type_id": "m6gd.4xlarge",
                            "num_workers": 4,
                        },
                    }
                }
            ),
            encoding="utf-8",
        )

        action = migrate_cluster_file(cluster_path, config_service)
        assert action == "bumped"

        document = yaml.safe_load(cluster_path.read_text(encoding="utf-8"))
        custom = document["cluster"]["custom_configurations"]
        assert "driver_node_type_id" not in custom
        assert custom["node_type_id"] == "m7gd.4xlarge"
        assert custom["num_workers"] == 4
        assert "validation" not in document

    def test_keeps_validation_for_legacy_prod(self, tmp_path: Path, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "prod")
        ConfigurationService._instance_cache.clear()
        config_service = ConfigurationService()

        cluster_path = tmp_path / "olos_dialer_cluster.yml"
        cluster_path.write_text(
            yaml.safe_dump(
                {
                    "cluster": {
                        "type": "databricks_16_4_med_general_cluster",
                    },
                    "validation": {
                        "cluster": {
                            "type": "consolidation_s_general_cluster",
                            "custom_configurations": {"num_workers": 3},
                        }
                    },
                }
            ),
            encoding="utf-8",
        )

        action = migrate_cluster_file(cluster_path, config_service)
        assert action == "validation_kept"
        document = yaml.safe_load(cluster_path.read_text(encoding="utf-8"))
        assert document["cluster"]["type"] == "databricks_16_4_med_general_cluster"
        assert document["validation"]["cluster"]["type"] == (
            "consolidation_s_general_cluster"
        )

    def test_promote_consolidation_prod_with_validation(
        self, tmp_path: Path, monkeypatch
    ):
        monkeypatch.setenv("ENVIRONMENT", "prod")
        ConfigurationService._instance_cache.clear()
        config_service = ConfigurationService()

        cluster_path = tmp_path / "enrich_attribution_cluster.yml"
        cluster_path.write_text(
            yaml.safe_dump(
                {
                    "cluster": {
                        "type": "consolidation_s_general_cluster",
                        "custom_configurations": {
                            "driver_node_type_id": "m6gd.xlarge",
                            "runtime_engine": "PHOTON",
                        },
                    },
                    "validation": {
                        "cluster": {
                            "type": "consolidation_xs_memory_cluster",
                            "custom_configurations": {
                                "num_workers": 3,
                                "runtime_engine": "PHOTON",
                            },
                        }
                    },
                }
            ),
            encoding="utf-8",
        )

        action = migrate_cluster_file(cluster_path, config_service)
        assert action == "promoted"
        document = yaml.safe_load(cluster_path.read_text(encoding="utf-8"))
        assert document["cluster"]["type"] == "consolidation_xs_memory_cluster"
        assert document["cluster"]["custom_configurations"]["num_workers"] == 3
        assert "validation" not in document
