"""Unit tests for cluster_validation_mapping."""

from __future__ import annotations

import pytest

from bietlejuice.services.configuration_service import ConfigurationService
from scripts.ci_cd.airflow_dag_builder.cluster_validation_mapping import (
    build_consolidation_catalog,
    build_validation_cluster_spec,
    compute_validation_overrides,
    is_single_node_cluster,
    map_instance_type_to_graviton,
    match_consolidation_preset,
    size_tier_from_instance_type,
)

pytest_plugins = ["test.unit.ci_cd.airflow_dag_builder.cluster_validation_prod_env"]


class TestMapInstanceTypeToGraviton:
    def test_general_m5a_to_m6g(self):
        # Arrange
        instance_type = "m5a.xlarge"
        expected = "m6g.xlarge"
        # Act
        result = map_instance_type_to_graviton(instance_type)
        # Assert
        assert result == expected

    def test_memory_r5a_to_r6g(self):
        # Arrange
        instance_type = "r5a.2xlarge"
        expected = "r6g.2xlarge"
        # Act
        result = map_instance_type_to_graviton(instance_type)
        # Assert
        assert result == expected

    def test_fleet_to_m6g(self):
        # Arrange
        instance_type = "m-fleet.xlarge"
        expected = "m6g.xlarge"
        # Act
        result = map_instance_type_to_graviton(instance_type)
        # Assert
        assert result == expected

    def test_size_tier_from_xlarge(self):
        # Arrange
        instance_type = "m6g.xlarge"
        expected = "s"
        # Act
        result = size_tier_from_instance_type(instance_type)
        # Assert
        assert result == expected


class TestMatchConsolidationPreset:
    @pytest.fixture(scope="class")
    def catalog(self):
        return build_consolidation_catalog(ConfigurationService())

    def test_med_general_three_workers(self, catalog):
        service = ConfigurationService()
        effective = service.get_config("databricks_16_4_med_general_cluster")
        matched = match_consolidation_preset(
            effective_prod=effective,
            prod_cluster_type="databricks_16_4_med_general_cluster",
            catalog=catalog,
        )
        assert matched is not None
        assert matched.name == "consolidation_s_general_cluster"
        assert matched.node_type_id == "m6g.xlarge"

    def test_custom_cluster_single_worker(self, catalog):
        effective = {
            "node_type_id": "m5a.large",
            "driver_node_type_id": "m5a.xlarge",
            "num_workers": 1,
            "spark_version": "13.3.x-scala2.12",
        }
        matched = match_consolidation_preset(
            effective_prod=effective,
            prod_cluster_type="custom_cluster",
            catalog=catalog,
        )
        assert matched is not None
        assert matched.name == "consolidation_xs_general_cluster"

    def test_rfleet_pool_preset_defaults_to_xlarge(self, catalog):
        service = ConfigurationService()
        effective = service.get_config("databricks_16_4_rfleet_instance_cluster")
        matched = match_consolidation_preset(
            effective_prod=effective,
            prod_cluster_type="databricks_16_4_rfleet_instance_cluster",
            catalog=catalog,
        )
        assert matched is not None
        assert matched.name == "consolidation_s_general_cluster"

    def test_prod_consolidation_m_memory_skips_when_only_match(self, catalog):
        service = ConfigurationService()
        effective = service.get_config("consolidation_m_memory_cluster")
        matched = match_consolidation_preset(
            effective_prod=effective,
            prod_cluster_type="consolidation_m_memory_cluster",
            catalog=catalog,
        )
        assert matched is None

    def test_fleet_single_node(self, catalog):
        # Arrange
        service = ConfigurationService()
        cluster_type = "databricks_16_4_small_general_fleet_xlarge_single_node"
        effective = service.get_config(cluster_type)
        # Act
        matched = match_consolidation_preset(
            effective_prod=effective,
            prod_cluster_type=cluster_type,
            catalog=catalog,
        )
        # Assert
        assert is_single_node_cluster(effective)
        assert matched is not None
        assert matched.name == "consolidation_s_general_single_node_cluster"


class TestComputeValidationOverrides:
    def test_skips_fields_equal_to_preset_defaults(self):
        overrides = compute_validation_overrides(
            effective_prod={
                "node_type_id": "m6g.xlarge",
                "driver_node_type_id": "m6g.xlarge",
                "num_workers": 2,
                "spark_version": "16.4.x-scala2.12",
            },
            mapped_worker="m6g.xlarge",
            mapped_driver="m6g.xlarge",
            validation_resolved={
                "node_type_id": "m6g.xlarge",
                "driver_node_type_id": "m6g.xlarge",
                "num_workers": 2,
                "spark_version": "16.4.x-scala2.12",
            },
        )
        assert overrides == {}

    def test_coerces_numeric_types(self):
        overrides = compute_validation_overrides(
            effective_prod={"num_workers": "3"},
            mapped_worker="m6g.xlarge",
            mapped_driver=None,
            validation_resolved={"num_workers": 3, "node_type_id": "m6g.xlarge"},
        )
        assert "num_workers" not in overrides


class TestBuildValidationClusterSpec:
    def test_med_general_includes_num_workers_override(self):
        declaration = {
            "dag": {"name": "test_dag"},
            "workflow": {"type": "query_delta", "layer": "enrich"},
            "cluster": {
                "type": "databricks_16_4_med_general_cluster",
                "databricks_conn_id": "databricks_new",
            },
        }
        spec = build_validation_cluster_spec(
            cluster_args=declaration["cluster"],
            declaration=declaration,
        )
        assert spec is not None
        assert spec.cluster_type == "consolidation_s_general_cluster"
        assert spec.custom_configurations.get("num_workers") == 3
        assert "node_type_id" not in spec.custom_configurations

    def test_custom_cluster_heterogeneous_driver_only(self):
        declaration = {
            "dag": {"name": "alert_manager"},
            "workflow": {
                "type": "query_delta",
                "layer": "enrich",
                "load_spark_job": "x",
            },
            "cluster": {
                "type": "custom_cluster",
                "custom_configurations": {
                    "node_type_id": "m5a.large",
                    "driver_node_type_id": "m5a.xlarge",
                    "num_workers": 1,
                    "spark_version": "13.3.x-scala2.12",
                },
            },
        }
        spec = build_validation_cluster_spec(
            cluster_args=declaration["cluster"],
            declaration=declaration,
        )
        assert spec is not None
        assert spec.cluster_type == "consolidation_xs_general_cluster"
        assert spec.allow_custom_spark_job is True
        assert spec.custom_configurations["spark_version"] == "13.3.x-scala2.12"
        assert spec.custom_configurations["num_workers"] == 1
        assert spec.custom_configurations["driver_node_type_id"] == "m6g.xlarge"
        assert "node_type_id" not in spec.custom_configurations

    def test_prod_consolidation_m_memory_omits_validation(self):
        declaration = {
            "dag": {"name": "databricks_usage"},
            "workflow": {"type": "query_delta", "layer": "enrich"},
            "cluster": {
                "type": "consolidation_m_memory_cluster",
                "databricks_conn_id": "databricks_new",
            },
        }
        spec = build_validation_cluster_spec(
            cluster_args=declaration["cluster"],
            declaration=declaration,
        )
        assert spec is None

    def test_prod_consolidation_s_general_omits_validation_when_only_match(self):
        declaration = {
            "dag": {"name": "enrich_cdc"},
            "workflow": {"type": "query_delta", "layer": "enrich"},
            "cluster": {
                "type": "consolidation_s_general_cluster",
                "databricks_conn_id": "databricks_new",
            },
        }
        spec = build_validation_cluster_spec(
            cluster_args=declaration["cluster"],
            declaration=declaration,
        )
        assert spec is None
