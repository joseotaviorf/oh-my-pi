"""Unit tests for cluster_validation_mapping."""

from __future__ import annotations

import pytest

from bietlejuice.services.configuration_service import ConfigurationService
from scripts.ci_cd.airflow_dag_builder.cluster_validation_mapping import (
    _mapped_worker_and_driver,
    build_consolidation_catalog,
    build_validation_cluster_spec,
    compute_validation_overrides,
    is_single_node_cluster,
    map_instance_type_to_graviton,
    match_consolidation_preset,
    merge_declaration_validation_custom_configurations,
    normalize_databricks_cluster_topology,
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

    def test_nine_and_twelve_xlarge_map_to_xl_tier(self):
        assert size_tier_from_instance_type("m5a.9xlarge") == "xl"
        assert size_tier_from_instance_type("m5a.12xlarge") == "xl"

    def test_aberrant_sizes_map_to_valid_graviton_sizes(self):
        assert map_instance_type_to_graviton("c5d.9xlarge") == "c6g.8xlarge"
        assert map_instance_type_to_graviton("c5.12xlarge") == "c6g.12xlarge"
        assert map_instance_type_to_graviton("m5a.12xlarge") == "m6g.12xlarge"
        assert map_instance_type_to_graviton("r5.12xlarge") == "r6g.12xlarge"
        assert map_instance_type_to_graviton("m5a.8xlarge") == "m6g.8xlarge"

    def test_memory_fleet_passes_through_to_r6g(self):
        assert map_instance_type_to_graviton("r-fleet.4xlarge") == "r6g.4xlarge"

    def test_compute_fleet_passes_through_to_c6g(self):
        assert map_instance_type_to_graviton("c-fleet.2xlarge") == "c6g.2xlarge"

    def test_valid_graviton_sizes_pass_through_unchanged(self):
        assert map_instance_type_to_graviton("m5.16xlarge") == "m6g.16xlarge"
        assert map_instance_type_to_graviton("r5a.metal") == "r6g.metal"
        assert map_instance_type_to_graviton("m5a.medium") == "m6g.medium"
        assert size_tier_from_instance_type("m6g.16xlarge") == "xl"

    def test_photon_maps_to_nvme_graviton_family(self):
        assert (
            map_instance_type_to_graviton("m5d.xlarge", use_nvme=True) == "m6gd.xlarge"
        )
        assert (
            map_instance_type_to_graviton("r5d.2xlarge", use_nvme=True)
            == "r6gd.2xlarge"
        )
        assert (
            map_instance_type_to_graviton("c5a.2xlarge", use_nvme=True)
            == "c6gd.2xlarge"
        )
        assert (
            map_instance_type_to_graviton("m5d.xlarge", use_nvme=False) == "m6g.xlarge"
        )
        assert (
            map_instance_type_to_graviton("r5d.2xlarge", use_nvme=False)
            == "r6g.2xlarge"
        )
        assert (
            map_instance_type_to_graviton("c5a.2xlarge", use_nvme=False)
            == "c6g.2xlarge"
        )


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

    def test_rfleet_pool_preset_preserves_memory_family(self, catalog):
        service = ConfigurationService()
        effective = service.get_config("databricks_16_4_rfleet_instance_cluster")
        matched = match_consolidation_preset(
            effective_prod=effective,
            prod_cluster_type="databricks_16_4_rfleet_instance_cluster",
            catalog=catalog,
        )
        assert matched is not None
        assert matched.name == "consolidation_s_memory_cluster"
        assert matched.node_type_id == "r6g.xlarge"

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

    def test_emits_uncapped_oversized_driver(self):
        overrides = compute_validation_overrides(
            effective_prod={},
            mapped_worker="r6g.2xlarge",
            mapped_driver="r6g.4xlarge",
            validation_resolved={
                "node_type_id": "r6g.2xlarge",
                "driver_node_type_id": "r6g.2xlarge",
            },
        )
        assert overrides["driver_node_type_id"] == "r6g.4xlarge"

    def test_emits_people_instance_profile_arn_override(self):
        overrides = compute_validation_overrides(
            effective_prod={
                "aws_attributes": {
                    "instance_profile_arn": (
                        "{{ var.value.instance_profile_secret_arn_people }}"
                    ),
                },
            },
            mapped_worker="m6g.xlarge",
            mapped_driver=None,
            validation_resolved={
                "node_type_id": "m6g.xlarge",
                "aws_attributes": {
                    "instance_profile_arn": "{{ var.value.instance_profile_arn }}",
                },
            },
        )
        assert overrides["aws_attributes"] == {
            "instance_profile_arn": "{{ var.value.instance_profile_secret_arn_people }}",
        }

    def test_emits_ebs_volume_size_when_prod_differs_from_preset(self):
        overrides = compute_validation_overrides(
            effective_prod={
                "aws_attributes": {
                    "ebs_volume_size": 200,
                    "instance_profile_arn": "{{ var.value.instance_profile_arn }}",
                },
            },
            mapped_worker="m6g.xlarge",
            mapped_driver=None,
            validation_resolved={
                "node_type_id": "m6g.xlarge",
                "aws_attributes": {
                    "ebs_volume_size": 100,
                    "instance_profile_arn": "{{ var.value.instance_profile_arn }}",
                },
            },
        )
        assert overrides["aws_attributes"] == {"ebs_volume_size": 200}

    def test_omits_aws_attributes_when_prod_matches_preset(self):
        overrides = compute_validation_overrides(
            effective_prod={
                "aws_attributes": {
                    "ebs_volume_size": 100,
                    "instance_profile_arn": "{{ var.value.instance_profile_arn }}",
                },
            },
            mapped_worker="m6g.xlarge",
            mapped_driver=None,
            validation_resolved={
                "node_type_id": "m6g.xlarge",
                "aws_attributes": {
                    "ebs_volume_size": 100,
                    "instance_profile_arn": "{{ var.value.instance_profile_arn }}",
                },
            },
        )
        assert "aws_attributes" not in overrides

    def test_emits_generic_nested_and_list_diffs(self):
        overrides = compute_validation_overrides(
            effective_prod={
                "node_type_id": "m5a.xlarge",
                "driver_node_type_id": "m5a.xlarge",
                "spark_conf": {
                    "spark.scheduler.mode": "FAIR",
                    "spark.sql.shuffle.partitions": "24",
                },
                "spark_env_vars": {
                    "SPARK_RUNTIME": "databricks",
                    "CUSTOM_ENV": "enabled",
                },
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
            mapped_worker="m6g.xlarge",
            mapped_driver="m6g.xlarge",
            validation_resolved={
                "node_type_id": "m6g.xlarge",
                "driver_node_type_id": "m6g.xlarge",
                "spark_conf": {"spark.scheduler.mode": "FAIR"},
                "spark_env_vars": {"SPARK_RUNTIME": "databricks"},
                "init_scripts": [
                    {
                        "s3": {
                            "destination": (
                                "{{ var.value.artifacts_bucket }}/bi-etl-ejuice/init_script.sh"
                            ),
                            "region": "",
                        }
                    }
                ],
            },
        )

        assert "node_type_id" not in overrides
        assert "driver_node_type_id" not in overrides
        assert overrides["spark_conf"] == {"spark.sql.shuffle.partitions": "24"}
        assert overrides["spark_env_vars"] == {"CUSTOM_ENV": "enabled"}
        assert len(overrides["init_scripts"]) == 2
        assert "sedona-init.sh" in overrides["init_scripts"][0]["s3"]["destination"]

    def test_mapped_worker_and_driver_prefers_master_node_type_id(self):
        effective_prod = {
            "node_type_id": "m7g.2xlarge",
            "master_node_type_id": "m7g.xlarge",
            "driver_node_type_id": "m5a.large",
            "spark_version": "emr-7.12.0",
        }
        mapped_worker, mapped_driver = _mapped_worker_and_driver(
            effective_prod, "emr_7_12_consolidation_s_memory_cluster"
        )
        assert mapped_worker == "m6g.2xlarge"
        assert mapped_driver == "m6g.xlarge"

    def test_mapped_worker_and_driver_keeps_large_driver_uncapped(self):
        effective_prod = {
            "node_type_id": "r5a.xlarge",
            "driver_node_type_id": "r5a.8xlarge",
            "num_workers": 4,
            "spark_version": "16.4.x-scala2.12",
        }
        mapped_worker, mapped_driver = _mapped_worker_and_driver(
            effective_prod, "custom_cluster"
        )
        assert mapped_worker == "r6g.xlarge"
        assert mapped_driver == "r6g.8xlarge"

    def test_mapped_worker_rfleet_pool_resolves_to_memory(self):
        service = ConfigurationService()
        effective = service.get_config("databricks_16_4_rfleet_instance_cluster")
        mapped_worker, mapped_driver = _mapped_worker_and_driver(
            effective, "databricks_16_4_rfleet_instance_cluster"
        )
        assert mapped_worker == "r6g.xlarge"
        assert mapped_driver == "r6g.xlarge"

    def test_emr_preset_uses_master_node_type_id(self):
        resolved = ConfigurationService().get_config(
            "emr_7_12_consolidation_s_memory_cluster"
        )
        assert resolved.get("master_node_type_id") == "m7g.xlarge"
        assert "driver_node_type_id" not in resolved


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

    def test_excluded_dag_omits_validation(self):
        declaration = {
            "dag": {"name": "reverse_kyc"},
            "workflow": {
                "type": "load_access",
                "layer": "reverse",
                "load_spark_job": "load_reverse_kyc",
            },
            "cluster": {"type": "databricks_13_3_med_general_cluster"},
        }
        spec = build_validation_cluster_spec(
            cluster_args=declaration["cluster"],
            declaration=declaration,
        )
        assert spec is None

    def test_enrich_agent_reports_validation_allows_nested_not_null_workaround(self):
        declaration = {
            "dag": {"name": "enrich_agent_reports"},
            "workflow": {
                "type": "query_delta",
                "layer": "enrich",
                "tables_customization": {
                    "agent_support_tickets_by_month": {
                        "load_spark_job": "load_agent_support_tickets_by_month",
                    },
                },
            },
            "cluster": {
                "type": "databricks_16_4_med_general_cluster",
                "databricks_conn_id": "databricks_new_env",
            },
            "validation": {
                "cluster": {
                    "custom_configurations": {
                        "spark_conf": {
                            "spark.databricks.delta.constraints.allowUnenforcedNotNull.enabled": True,
                        },
                    },
                },
            },
        }
        spec = build_validation_cluster_spec(
            cluster_args=declaration["cluster"],
            declaration=declaration,
        )
        assert spec is not None
        assert spec.allow_custom_spark_job is True
        spark_conf = spec.custom_configurations["spark_conf"]
        assert (
            spark_conf[
                "spark.databricks.delta.constraints.allowUnenforcedNotNull.enabled"
            ]
            is True
        )

    def test_existing_validation_custom_config_does_not_override_generated_values(self):
        declaration = {
            "validation": {
                "cluster": {
                    "custom_configurations": {
                        "num_workers": 999,
                        "init_scripts": [{"s3": {"destination": "stale.sh"}}],
                        "spark_conf": {
                            "spark.sql.shuffle.partitions": "stale",
                            "spark.manual.override": "true",
                        },
                    },
                },
            },
        }
        custom_configurations = {
            "num_workers": 3,
            "spark_conf": {"spark.sql.shuffle.partitions": "24"},
        }

        merged = merge_declaration_validation_custom_configurations(
            declaration, custom_configurations
        )

        assert merged["num_workers"] == 3
        assert "init_scripts" not in merged
        assert merged["spark_conf"] == {
            "spark.sql.shuffle.partitions": "24",
            "spark.manual.override": "true",
        }

    def test_photon_declaration_overrides(self):
        declaration = {
            "dag": {"name": "dw_user"},
            "workflow": {"type": "query_delta", "layer": "dw"},
            "cluster": {
                "type": "databricks_16_4_med_general_photon_cluster",
                "databricks_conn_id": "databricks_new_env",
            },
        }
        spec = build_validation_cluster_spec(
            cluster_args=declaration["cluster"],
            declaration=declaration,
        )
        assert spec is not None
        assert spec.cluster_type == "consolidation_s_general_cluster"
        assert spec.custom_configurations["node_type_id"] == "m6gd.xlarge"
        assert spec.custom_configurations["driver_node_type_id"] == "m6gd.xlarge"
        assert spec.custom_configurations["runtime_engine"] == "PHOTON"
        assert spec.custom_configurations["num_workers"] == 3

    def test_enrich_ebdb_contract_aberrant_compute_worker(self):
        declaration = {
            "dag": {"name": "enrich_ebdb_contract"},
            "workflow": {"type": "query_delta", "layer": "enrich"},
            "cluster": {
                "type": "custom_cluster",
                "custom_configurations": {
                    "driver_node_type_id": "m5a.2xlarge",
                    "node_type_id": "c5d.9xlarge",
                    "num_workers": 2,
                    "spark_version": "16.4.x-scala2.12",
                },
                "databricks_conn_id": "databricks_new_env",
            },
        }
        spec = build_validation_cluster_spec(
            cluster_args=declaration["cluster"],
            declaration=declaration,
        )
        assert spec is not None
        assert spec.cluster_type == "consolidation_xl_compute_cluster"
        assert "node_type_id" not in spec.custom_configurations
        assert spec.custom_configurations["driver_node_type_id"] == "m6g.2xlarge"
        assert spec.custom_configurations.get("num_workers", 2) == 2

    def test_enrich_visit_aberrant_compute_worker(self):
        declaration = {
            "dag": {"name": "enrich_visit"},
            "workflow": {"type": "query_delta", "layer": "enrich"},
            "cluster": {
                "type": "custom_cluster",
                "custom_configurations": {
                    "driver_node_type_id": "r5.2xlarge",
                    "node_type_id": "c5.12xlarge",
                    "num_workers": 8,
                    "spark_version": "16.4.x-scala2.12",
                },
                "databricks_conn_id": "databricks_new_env",
            },
        }
        spec = build_validation_cluster_spec(
            cluster_args=declaration["cluster"],
            declaration=declaration,
        )
        assert spec is not None
        assert spec.cluster_type == "consolidation_xl_compute_cluster"
        assert spec.custom_configurations["node_type_id"] == "c6g.12xlarge"
        assert spec.custom_configurations["driver_node_type_id"] == "r6g.2xlarge"
        assert spec.custom_configurations["num_workers"] == 8

    def test_sedona_preset_emits_preset_only_init_scripts(self):
        declaration = {
            "dag": {"name": "ebdb_location"},
            "workflow": {"type": "query_delta", "layer": "enrich"},
            "cluster": {
                "type": "custom_cluster_with_sedona",
                "custom_configurations": {
                    "driver_node_type_id": "m6g.xlarge",
                    "node_type_id": "m6g.xlarge",
                    "num_workers": 3,
                    "spark_version": "16.4.x-scala2.12",
                    "spark_conf": {
                        "spark.serializer": (
                            "org.apache.spark.serializer.KryoSerializer"
                        ),
                    },
                },
                "databricks_conn_id": "databricks_new",
                "custom_libraries": [
                    {
                        "maven": {
                            "coordinates": (
                                "org.apache.sedona:"
                                "sedona-python-adapter-3.0_2.12:1.2.1-incubating"
                            ),
                        },
                    },
                ],
            },
        }

        spec = build_validation_cluster_spec(
            cluster_args=declaration["cluster"],
            declaration=declaration,
        )

        assert spec is not None
        assert spec.cluster_type == "consolidation_s_general_cluster"
        assert spec.custom_libraries == declaration["cluster"]["custom_libraries"]
        init_scripts = spec.custom_configurations["init_scripts"]
        assert len(init_scripts) == 2
        assert "sedona-init.sh" in init_scripts[0]["s3"]["destination"]
        assert "init_script.sh" in init_scripts[1]["s3"]["destination"]


class TestNormalizeDatabricksClusterTopology:
    def test_maps_legacy_custom_cluster_types_to_graviton(self):
        cluster_args = {
            "type": "custom_cluster",
            "custom_configurations": {
                "driver_node_type_id": "m5a.xlarge",
                "node_type_id": "m5a.large",
                "num_workers": 1,
            },
        }
        normalized = normalize_databricks_cluster_topology(
            cluster_args, ConfigurationService()
        )
        custom = normalized["custom_configurations"]
        assert custom["driver_node_type_id"] == "m6g.xlarge"
        assert custom["node_type_id"] == "m6g.large"
        assert custom["num_workers"] == 1

    def test_maps_consolidation_worker_override_to_graviton(self):
        cluster_args = {
            "type": "consolidation_m_general_cluster",
            "custom_configurations": {
                "driver_node_type_id": "m6g.xlarge",
                "node_type_id": "m5a.2xlarge",
            },
        }
        normalized = normalize_databricks_cluster_topology(
            cluster_args, ConfigurationService()
        )
        assert normalized["custom_configurations"]["node_type_id"] == "m6g.2xlarge"

    def test_no_op_for_emr_cluster(self):
        cluster_args = {
            "type": "emr_7_12_min_general_2_workers_cluster",
            "custom_configurations": {
                "node_type_id": "m7g.2xlarge",
            },
        }
        normalized = normalize_databricks_cluster_topology(
            cluster_args, ConfigurationService()
        )
        assert normalized["custom_configurations"]["node_type_id"] == "m7g.2xlarge"

    def test_emr_normalizes_flat_instance_count_to_task_nodes(self):
        from scripts.ci_cd.airflow_dag_builder.cluster_validation_mapping import (
            normalize_emr_cluster_topology,
        )

        cluster_args = {
            "type": "emr_7_12_min_memory_3_workers_cluster",
            "custom_configurations": {
                "instance_count": 1,
            },
        }
        normalized = normalize_emr_cluster_topology(cluster_args)
        custom = normalized["custom_configurations"]
        assert "instance_count" not in custom
        assert custom["task_nodes"]["instance_count"] == 1

    def test_emr_normalizes_num_task_workers_to_task_nodes(self):
        from scripts.ci_cd.airflow_dag_builder.cluster_validation_mapping import (
            normalize_emr_cluster_topology,
        )

        cluster_args = {
            "type": "emr_7_12_consolidation_s_general_cluster",
            "custom_configurations": {
                "num_workers": 3,
                "num_task_workers": 2,
            },
        }
        normalized = normalize_emr_cluster_topology(cluster_args)
        custom = normalized["custom_configurations"]
        assert "num_workers" not in custom
        assert "num_task_workers" not in custom
        assert custom["core_nodes"]["instance_count"] == 1
        assert custom["task_nodes"]["instance_count"] == 2

    def test_heterogeneous_driver_and_worker_preserve_class(self):
        cluster_args = {
            "type": "consolidation_s_memory_cluster",
            "custom_configurations": {
                "driver_node_type_id": "m5d.xlarge",
                "node_type_id": "r5d.2xlarge",
            },
        }
        normalized = normalize_databricks_cluster_topology(
            cluster_args, ConfigurationService()
        )
        custom = normalized["custom_configurations"]
        assert custom["driver_node_type_id"] == "m6g.xlarge"
        assert custom["node_type_id"] == "r6g.2xlarge"
