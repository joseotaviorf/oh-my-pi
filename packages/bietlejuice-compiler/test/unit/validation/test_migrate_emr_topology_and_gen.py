"""Unit tests for migrate_emr_topology_and_gen."""

from __future__ import annotations

import yaml

from bietlejuice.services.configuration_service import ConfigurationService
from scripts.validation.migrate_emr_topology_and_gen import migrate_cluster_file

pytest_plugins = [
    "test.unit.ci_cd.airflow_dag_builder.cluster_validation_prod_env",
]


class TestMigrateEmrTopologyAndGen:
    def test_rebalances_three_worker_validation_block(self, tmp_path, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "prod")
        ConfigurationService._instance_cache.clear()

        cluster_path = tmp_path / "sample_cluster.yml"
        cluster_path.write_text(
            """cluster:
  type: consolidation_m_general_cluster
  databricks_conn_id: databricks_new
validation:
  cluster:
    type: emr_7_12_consolidation_m_general_cluster
    custom_configurations:
      core_nodes:
        instance_count: 1
      task_nodes:
        instance_count: 2
""",
            encoding="utf-8",
        )

        actions = migrate_cluster_file(cluster_path, ConfigurationService())
        assert actions is not None
        assert "rebalanced" in actions

        document = yaml.safe_load(cluster_path.read_text(encoding="utf-8"))
        custom = document["validation"]["cluster"]["custom_configurations"]
        assert custom["core_nodes"]["instance_count"] == 2
        assert custom["task_nodes"]["instance_count"] == 1

    def test_skips_databricks_only_cluster(self, tmp_path, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "prod")
        ConfigurationService._instance_cache.clear()

        cluster_path = tmp_path / "dbr_only_cluster.yml"
        cluster_path.write_text(
            """cluster:
  type: consolidation_s_memory_cluster
  databricks_conn_id: databricks_new
""",
            encoding="utf-8",
        )

        assert migrate_cluster_file(cluster_path, ConfigurationService()) is None
