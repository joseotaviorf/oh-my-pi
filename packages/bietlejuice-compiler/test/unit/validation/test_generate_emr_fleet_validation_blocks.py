"""Unit tests for generate_emr_fleet_validation_blocks."""

from __future__ import annotations

import yaml

from bietlejuice.services.configuration_service import ConfigurationService
from scripts.validation.generate_emr_fleet_validation_blocks import (
    build_emr_effective_from_databricks,
    build_validation_block,
    extract_preserved_custom_config,
    map_to_emr_fleet_preset,
)

pytest_plugins = [
    "test.unit.ci_cd.airflow_dag_builder.cluster_validation_prod_env",
]


class TestMapToEmrFleetPreset:
    def test_xs_memory(self):
        assert (
            map_to_emr_fleet_preset("consolidation_xs_memory_cluster")
            == "emr_7_12_consolidation_xs_memory_fleet_cluster"
        )

    def test_single_node(self):
        assert (
            map_to_emr_fleet_preset("consolidation_l_memory_single_node_cluster")
            == "emr_7_12_consolidation_l_memory_single_node_fleet_cluster"
        )


class TestBuildEmrEffectiveFromDatabricks:
    def test_three_workers_split(self, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "prod")
        ConfigurationService._instance_cache.clear()
        service = ConfigurationService()

        effective = {
            "node_type_id": "r7g.large",
            "driver_node_type_id": "r7g.xlarge",
            "num_workers": 3,
            "aws_attributes": {"availability": "SPOT"},
        }
        emr = build_emr_effective_from_databricks(
            effective, "consolidation_xs_memory_cluster", service
        )
        assert emr["core_nodes"]["instance_count"] == 2
        assert emr["task_nodes"]["instance_count"] == 1
        assert emr["master_node_type_id"] == "r6g.xlarge"

    def test_single_node_master_at_least_2xlarge(self, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "prod")
        ConfigurationService._instance_cache.clear()
        service = ConfigurationService()

        effective = {
            "driver_node_type_id": "r7g.xlarge",
            "num_workers": 0,
            "spark_conf": {"spark.databricks.cluster.profile": "singleNode"},
        }
        emr = build_emr_effective_from_databricks(
            effective, "consolidation_s_memory_single_node_cluster", service
        )
        assert emr["master_node_type_id"] == "r6g.2xlarge"

    def test_single_node_bumps_fleet_preset_tier(self, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "prod")
        ConfigurationService._instance_cache.clear()
        service = ConfigurationService()

        prod_cluster = {
            "type": "consolidation_s_memory_single_node_cluster",
            "databricks_conn_id": "databricks_new_env",
        }
        validation = build_validation_block(prod_cluster, {}, service)
        assert (
            validation["cluster"]["type"]
            == "emr_7_12_consolidation_m_memory_single_node_fleet_cluster"
        )


class TestExtractPreservedCustomConfig:
    def test_people_instance_profile(self):
        prod_cluster = {
            "custom_configurations": {
                "aws_attributes": {
                    "instance_profile_arn": "{{ var.value.instance_profile_secret_arn_people }}"
                }
            }
        }
        preserved = extract_preserved_custom_config(prod_cluster, {})
        assert preserved["aws_attributes"]["instance_profile_arn"] == (
            "{{ var.value.emr_instance_profile_arn_people }}"
        )

    def test_strips_databricks_spark_conf(self):
        prod_cluster = {
            "custom_configurations": {
                "spark_conf": {
                    "spark.databricks.sql.initial.catalog.namespace": "quintoandar_prod",
                    "spark.sql.shuffle.partitions": "200",
                }
            }
        }
        preserved = extract_preserved_custom_config(prod_cluster, {})
        assert "spark.databricks.sql.initial.catalog.namespace" not in preserved.get(
            "spark_conf", {}
        )
        assert preserved["spark_conf"]["spark.sql.shuffle.partitions"] == "200"

    def test_databricks_only_spark_conf_emits_empty_dict(self):
        prod_cluster = {
            "custom_configurations": {
                "spark_conf": {
                    "spark.databricks.sql.initial.catalog.namespace": "quintoandar_prod",
                }
            }
        }
        preserved = extract_preserved_custom_config(prod_cluster, {})
        assert preserved["spark_conf"] == {}


class TestBuildValidationBlock:
    def test_xs_memory_three_workers_fleet(self, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "prod")
        ConfigurationService._instance_cache.clear()
        service = ConfigurationService()

        prod_cluster = {
            "type": "consolidation_xs_memory_cluster",
            "databricks_conn_id": "databricks_new_env",
            "custom_configurations": {"num_workers": 3},
        }
        validation = build_validation_block(prod_cluster, {}, service)
        assert validation is not None
        assert (
            validation["cluster"]["type"]
            == "emr_7_12_consolidation_xs_memory_fleet_cluster"
        )
        task_nodes = validation["cluster"]["custom_configurations"]["task_nodes"]
        assert task_nodes["target_spot"] == 1
        assert task_nodes["target_on_demand"] == 0

    def test_load_spark_job_sets_allow_flag(self, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "prod")
        ConfigurationService._instance_cache.clear()
        service = ConfigurationService()

        prod_cluster = {
            "type": "consolidation_s_memory_cluster",
            "databricks_conn_id": "databricks_new",
        }
        declaration = {"workflow": {"load_spark_job": "istio_logs_load"}}
        validation = build_validation_block(prod_cluster, declaration, service)
        assert validation["allow_custom_spark_job"] is True

    def test_photon_not_in_validation(self, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "prod")
        ConfigurationService._instance_cache.clear()
        service = ConfigurationService()

        prod_cluster = {
            "type": "consolidation_l_memory_single_node_cluster",
            "databricks_conn_id": "databricks_new_env",
            "custom_configurations": {"runtime_engine": "PHOTON"},
        }
        validation = build_validation_block(prod_cluster, {}, service)
        custom = validation["cluster"].get("custom_configurations") or {}
        assert "runtime_engine" not in custom

    def test_metric_people_people_profile(self, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "prod")
        ConfigurationService._instance_cache.clear()
        service = ConfigurationService()

        prod_cluster = {
            "type": "consolidation_xs_memory_cluster",
            "databricks_conn_id": "databricks_new_env",
            "custom_configurations": {
                "num_workers": 3,
                "aws_attributes": {
                    "instance_profile_arn": (
                        "{{ var.value.instance_profile_secret_arn_people }}"
                    )
                },
            },
        }
        validation = build_validation_block(prod_cluster, {}, service)
        aws = validation["cluster"]["custom_configurations"]["aws_attributes"]
        assert aws["instance_profile_arn"] == (
            "{{ var.value.emr_instance_profile_arn_people }}"
        )

    def test_databricks_only_spark_conf_emits_empty_spark_conf(self, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "prod")
        ConfigurationService._instance_cache.clear()
        service = ConfigurationService()

        prod_cluster = {
            "type": "consolidation_s_general_cluster",
            "databricks_conn_id": "databricks_new_env",
            "custom_configurations": {
                "spark_conf": {
                    "spark.databricks.sql.initial.catalog.namespace": (
                        "quintoandar_{{ var.value.environment }}"
                    ),
                },
            },
        }
        validation = build_validation_block(prod_cluster, {}, service)
        assert validation["cluster"]["custom_configurations"]["spark_conf"] == {}


class TestApplyValidationToClusterFile:
    def test_writes_validation_block(self, tmp_path, monkeypatch):
        monkeypatch.setenv("ENVIRONMENT", "prod")
        ConfigurationService._instance_cache.clear()

        from scripts.validation.generate_emr_fleet_validation_blocks import (
            apply_validation_to_cluster_file,
        )

        cluster_path = tmp_path / "sample_cluster.yml"
        cluster_path.write_text(
            """cluster:
  type: consolidation_xs_memory_cluster
  databricks_conn_id: databricks_new_env
  custom_configurations:
    num_workers: 3
""",
            encoding="utf-8",
        )

        result = apply_validation_to_cluster_file(
            cluster_path, {}, ConfigurationService()
        )
        assert result == "updated"
        document = yaml.safe_load(cluster_path.read_text(encoding="utf-8"))
        assert document["validation"]["cluster"]["type"].endswith("_fleet_cluster")
