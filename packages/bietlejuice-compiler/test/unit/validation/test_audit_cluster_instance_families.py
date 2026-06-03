"""Unit tests for audit_cluster_instance_families."""

from __future__ import annotations

from pathlib import Path

import pytest
import yaml

from bietlejuice.services.configuration_service import ConfigurationService
from scripts.validation.audit_cluster_instance_families import (
    audit_cluster_file,
    generation_variant_key,
    is_graviton_6g_family,
)

pytest_plugins = [
    "test.unit.ci_cd.airflow_dag_builder.cluster_validation_prod_env",
]

REPO_ROOT = Path(__file__).resolve().parents[4]


class TestInstanceParsing:
    def test_generation_variant_key_m6gd_normalizes_to_6g(self):
        assert generation_variant_key("m6gd.2xlarge") == "6g"

    def test_is_graviton_6g_family_accepts_gd(self):
        assert is_graviton_6g_family("r6gd.4xlarge")

    def test_is_graviton_6g_family_rejects_bare_gen6_intel(self):
        assert not is_graviton_6g_family("m6.xlarge")


class TestAuditClusterFile:
    @pytest.fixture
    def config_service(self) -> ConfigurationService:
        return ConfigurationService()

    def test_metabase_pull_heterogeneous_6g_is_compliant(
        self, config_service: ConfigurationService, tmp_path: Path
    ):
        cluster_path = tmp_path / "metabase_pull_cluster.yml"
        cluster_path.write_text(
            yaml.safe_dump(
                {
                    "cluster": {
                        "type": "consolidation_s_memory_cluster",
                        "custom_configurations": {
                            "driver_node_type_id": "m6g.xlarge",
                            "node_type_id": "r6g.xlarge",
                        },
                    }
                }
            ),
            encoding="utf-8",
        )
        violations = audit_cluster_file(cluster_path, config_service)
        assert violations == []

    def test_consolidation_m5_worker_is_violation(
        self, config_service: ConfigurationService, tmp_path: Path
    ):
        cluster_path = tmp_path / "enrich_health_metrics_cluster.yml"
        cluster_path.write_text(
            yaml.safe_dump(
                {
                    "cluster": {
                        "type": "consolidation_m_general_cluster",
                        "custom_configurations": {
                            "driver_node_type_id": "m6g.xlarge",
                            "node_type_id": "m5a.2xlarge",
                        },
                    }
                }
            ),
            encoding="utf-8",
        )
        violations = audit_cluster_file(cluster_path, config_service)
        assert len(violations) == 1
        assert violations[0].reason in (
            "generation_variant_mismatch",
            "databricks_consolidation_requires_6g_family",
        )

    def test_legacy_databricks_preset_with_graviton_override_is_compliant(
        self, config_service: ConfigurationService, tmp_path: Path
    ):
        cluster_path = tmp_path / "dw_recon_quintocred_cluster.yml"
        cluster_path.write_text(
            yaml.safe_dump(
                {
                    "cluster": {
                        "type": "databricks_13_3_min_general_cluster",
                        "custom_configurations": {
                            "driver_node_type_id": "m6g.2xlarge",
                            "node_type_id": "m6g.xlarge",
                        },
                    }
                }
            ),
            encoding="utf-8",
        )
        violations = audit_cluster_file(cluster_path, config_service)
        assert violations == []

    def test_emr_min_m7g_explicit_override_is_compliant(
        self, config_service: ConfigurationService, tmp_path: Path
    ):
        cluster_path = tmp_path / "bob_cluster.yml"
        cluster_path.write_text(
            yaml.safe_dump(
                {
                    "cluster": {
                        "type": "emr_7_12_min_general_2_workers_cluster",
                        "custom_configurations": {
                            "master_node_type_id": "m7g.xlarge",
                            "node_type_id": "m7g.2xlarge",
                        },
                    }
                }
            ),
            encoding="utf-8",
        )
        violations = audit_cluster_file(cluster_path, config_service)
        assert violations == []

    def test_emr_min_memory_m7a_worker_override_is_compliant(
        self, config_service: ConfigurationService, tmp_path: Path
    ):
        cluster_path = tmp_path / "betopera_cluster.yml"
        cluster_path.write_text(
            yaml.safe_dump(
                {
                    "cluster": {
                        "type": "emr_7_12_min_memory_3_workers_cluster",
                        "custom_configurations": {
                            "master_node_type_id": "m7a.xlarge",
                            "node_type_id": "m7a.2xlarge",
                        },
                    }
                }
            ),
            encoding="utf-8",
        )
        violations = audit_cluster_file(cluster_path, config_service)
        assert violations == []
