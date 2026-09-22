"""Unit tests for cluster_validation_mapping."""

from __future__ import annotations

from pathlib import Path

import pytest
import yaml

from bietlejuice.base.airflow.cluster_config_resolver import merge_cluster_configuration
from bietlejuice.base.validation.cluster_args import merge_validation_cluster_args
from bietlejuice.services.configuration_service import ConfigurationService
from scripts.ci_cd.airflow_dag_builder.cluster_validation_mapping import (
    _has_load_spark_job,
    _instance_family,
    _is_legacy_nvme_instance_type,
    _mapped_worker_and_driver,
    _use_nvme_for_topology_value,
    build_consolidation_catalog,
    build_rightsizing_validation_cluster_spec,
    build_validation_cluster_spec,
    compute_validation_overrides,
    is_single_node_cluster,
    map_instance_type_to_graviton,
    match_consolidation_preset,
    merge_declaration_validation_custom_configurations,
    normalize_databricks_cluster_topology,
    size_tier_from_instance_type,
    strip_redundant_preset_default_overrides,
)

pytest_plugins = ["test.unit.ci_cd.airflow_dag_builder.cluster_validation_prod_env"]


class TestMapInstanceTypeToGraviton:
    def test_general_m5a_to_m6g(self):
        # Arrange
        instance_type = "m5a.xlarge"
        expected = "m7g.xlarge"
        # Act
        result = map_instance_type_to_graviton(instance_type)
        # Assert
        assert result == expected

    def test_memory_r5a_to_r6g(self):
        # Arrange
        instance_type = "r5a.2xlarge"
        expected = "r7g.2xlarge"
        # Act
        result = map_instance_type_to_graviton(instance_type)
        # Assert
        assert result == expected

    def test_fleet_to_m6g(self):
        # Arrange
        instance_type = "m-fleet.xlarge"
        expected = "m7g.xlarge"
        # Act
        result = map_instance_type_to_graviton(instance_type)
        # Assert
        assert result == expected

    def test_size_tier_from_xlarge(self):
        # Arrange
        instance_type = "m7g.xlarge"
        expected = "s"
        # Act
        result = size_tier_from_instance_type(instance_type)
        # Assert
        assert result == expected

    def test_nine_and_twelve_xlarge_map_to_xl_tier(self):
        assert size_tier_from_instance_type("m5a.9xlarge") == "xl"
        assert size_tier_from_instance_type("m5a.12xlarge") == "xl"

    def test_aberrant_sizes_map_to_valid_graviton_sizes(self):
        assert map_instance_type_to_graviton("c5d.9xlarge") == "c7g.8xlarge"
        assert map_instance_type_to_graviton("c5.12xlarge") == "c7g.12xlarge"
        assert map_instance_type_to_graviton("m5a.12xlarge") == "m7g.12xlarge"
        assert map_instance_type_to_graviton("r5.12xlarge") == "r7g.12xlarge"
        assert map_instance_type_to_graviton("m5a.8xlarge") == "m7g.8xlarge"

    def test_memory_fleet_passes_through_to_r6g(self):
        assert map_instance_type_to_graviton("r-fleet.4xlarge") == "r7g.4xlarge"

    def test_compute_fleet_passes_through_to_c6g(self):
        assert map_instance_type_to_graviton("c-fleet.2xlarge") == "c7g.2xlarge"

    def test_valid_graviton_sizes_pass_through_unchanged(self):
        assert map_instance_type_to_graviton("m5.16xlarge") == "m7g.16xlarge"
        assert map_instance_type_to_graviton("r5a.metal") == "r7g.metal"
        assert map_instance_type_to_graviton("m5a.medium") == "m7g.medium"
        assert size_tier_from_instance_type("m7g.16xlarge") == "xl"

    def test_photon_maps_to_nvme_graviton_family(self):
        assert (
            map_instance_type_to_graviton("m5d.xlarge", use_nvme=True) == "m7gd.xlarge"
        )
        assert (
            map_instance_type_to_graviton("r5d.2xlarge", use_nvme=True)
            == "r7gd.2xlarge"
        )
        assert (
            map_instance_type_to_graviton("c5a.2xlarge", use_nvme=True)
            == "c7gd.2xlarge"
        )
        assert (
            map_instance_type_to_graviton("m5d.xlarge", use_nvme=False) == "m7g.xlarge"
        )
        assert (
            map_instance_type_to_graviton("r5d.2xlarge", use_nvme=False)
            == "r7g.2xlarge"
        )
        assert (
            map_instance_type_to_graviton("c5a.2xlarge", use_nvme=False)
            == "c7g.2xlarge"
        )


def _map_worker_topology(instance_type: str) -> str:
    """Worker-side mapping: NVMe policy resolved as topology normalization does."""
    use_nvme = _use_nvme_for_topology_value(instance_type, photon_enabled=False)
    return map_instance_type_to_graviton(instance_type, use_nvme=use_nvme)


class TestStorageFamilyToGraviton:
    @pytest.mark.parametrize(
        ("instance_type", "expected"),
        [
            ("i3.2xlarge", "r7gd.2xlarge"),
            ("i4i.4xlarge", "r7gd.4xlarge"),
            ("i4i.8xlarge", "r7gd.8xlarge"),
            ("i7i.2xlarge", "r7gd.2xlarge"),
            ("i7i.4xlarge", "r7gd.4xlarge"),
            ("rd-fleet.8xlarge", "r7gd.8xlarge"),
        ],
    )
    def test_worker_keeps_nvme_on_graviton_memory(self, instance_type, expected):
        assert _map_worker_topology(instance_type) == expected

    @pytest.mark.parametrize(
        ("instance_type", "expected"),
        [
            ("i3.2xlarge", "r7g.2xlarge"),
            ("i7i.xlarge", "r7g.xlarge"),
            ("rd-fleet.2xlarge", "r7g.2xlarge"),
        ],
    )
    def test_driver_drops_nvme(self, instance_type, expected):
        assert map_instance_type_to_graviton(instance_type, use_nvme=False) == expected

    @pytest.mark.parametrize("use_nvme", [True, False])
    @pytest.mark.parametrize("instance_type", ["i8g.2xlarge", "i4g.2xlarge"])
    def test_arm_storage_passes_through_unchanged(self, instance_type, use_nvme):
        assert (
            map_instance_type_to_graviton(instance_type, use_nvme=use_nvme)
            == instance_type
        )
        assert _map_worker_topology(instance_type) == instance_type

    @pytest.mark.parametrize(
        "instance_type",
        [
            "i3.2xlarge",
            "i4i.4xlarge",
            "i7i.2xlarge",
            "i4g.2xlarge",
            "i8g.2xlarge",
            "rd-fleet.8xlarge",
        ],
    )
    def test_storage_families_classified_as_memory(self, instance_type):
        assert _instance_family(instance_type) == "memory"

    @pytest.mark.parametrize(
        ("instance_type", "expected_tier"),
        [
            ("i3.2xlarge", "m"),
            ("i7i.2xlarge", "m"),
            ("i7i.4xlarge", "l"),
            ("i4i.4xlarge", "l"),
            ("i4i.8xlarge", "xl"),
            ("rd-fleet.8xlarge", "xl"),
        ],
    )
    def test_storage_size_tiers(self, instance_type, expected_tier):
        assert size_tier_from_instance_type(instance_type) == expected_tier

    @pytest.mark.parametrize(
        "instance_type",
        [
            "i3.2xlarge",
            "i3en.2xlarge",
            "i4i.4xlarge",
            "i7i.2xlarge",
            "rd-fleet.8xlarge",
        ],
    )
    def test_legacy_nvme_detection_true_for_storage_families(self, instance_type):
        assert _is_legacy_nvme_instance_type(instance_type) is True

    @pytest.mark.parametrize(
        "instance_type",
        ["m4.xlarge", "c7a.4xlarge", "r7g.2xlarge", "i8g.2xlarge", "i4g.2xlarge"],
    )
    def test_legacy_nvme_detection_false_for_non_nvme_and_arm(self, instance_type):
        assert _is_legacy_nvme_instance_type(instance_type) is False


class TestLegacyGeneralComputeFamilies:
    @pytest.mark.parametrize(
        ("instance_type", "expected"),
        [
            ("m4.xlarge", "m7g.xlarge"),
            ("m4.2xlarge", "m7g.2xlarge"),
            ("m4.4xlarge", "m7g.4xlarge"),
            ("c7a.4xlarge", "c7g.4xlarge"),
        ],
    )
    def test_worker_and_driver_map_identically(self, instance_type, expected):
        # Arrange / Act
        worker = _map_worker_topology(instance_type)
        driver = map_instance_type_to_graviton(instance_type, use_nvme=False)
        # Assert: these families carry no local NVMe, so worker == driver
        assert worker == expected
        assert driver == expected

    def test_m4_classified_as_general(self):
        assert _instance_family("m4.xlarge") == "general"

    def test_c7a_classified_as_compute(self):
        assert _instance_family("c7a.4xlarge") == "compute"

    def test_c7a_4xlarge_is_l_tier(self):
        assert size_tier_from_instance_type("c7a.4xlarge") == "l"


class TestMatchConsolidationPreset:
    @pytest.fixture(scope="class")
    def catalog(self):
        # Production (build_validation_cluster_spec) always hands the matcher a
        # flavor-filtered pool: non-wonka DAGs never see wonka_consolidation_*
        # twins. Mirror that here — these tests pin generic-preset behavior.
        return [
            preset
            for preset in build_consolidation_catalog(ConfigurationService())
            if not preset.name.startswith("wonka_consolidation_")
        ]

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
        assert matched.node_type_id == "m7g.xlarge"

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
        assert matched.node_type_id == "r7g.xlarge"

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


class TestBuildConsolidationCatalogWonkaTwins:
    def test_wonka_twin_shares_topology_and_pins_wonka_runtime(self):
        catalog = build_consolidation_catalog(ConfigurationService())
        by_name = {preset.name: preset for preset in catalog}
        generic = by_name["consolidation_m_memory_cluster"]
        wonka = by_name["wonka_consolidation_m_memory_cluster"]
        assert wonka.family == "memory"
        assert wonka.size_tier == "m"
        # Wonka prod jobs run 15.4; validation must mirror the prod runtime.
        assert wonka.spark_version == "15.4.x-scala2.12"
        assert wonka.node_type_id == generic.node_type_id


class TestComputeValidationOverrides:
    def test_skips_fields_equal_to_preset_defaults(self):
        overrides = compute_validation_overrides(
            effective_prod={
                "node_type_id": "m7g.xlarge",
                "driver_node_type_id": "m7g.xlarge",
                "num_workers": 2,
                "spark_version": "16.4.x-scala2.12",
            },
            mapped_worker="m7g.xlarge",
            mapped_driver="m7g.xlarge",
            validation_resolved={
                "node_type_id": "m7g.xlarge",
                "driver_node_type_id": "m7g.xlarge",
                "num_workers": 2,
                "spark_version": "16.4.x-scala2.12",
            },
        )
        assert overrides == {}

    def test_coerces_numeric_types(self):
        overrides = compute_validation_overrides(
            effective_prod={"num_workers": "3"},
            mapped_worker="m7g.xlarge",
            mapped_driver=None,
            validation_resolved={"num_workers": 3, "node_type_id": "m7g.xlarge"},
        )
        assert "num_workers" not in overrides

    def test_emits_uncapped_oversized_driver(self):
        overrides = compute_validation_overrides(
            effective_prod={},
            mapped_worker="r7g.2xlarge",
            mapped_driver="r7g.4xlarge",
            validation_resolved={
                "node_type_id": "r7g.2xlarge",
                "driver_node_type_id": "r7g.2xlarge",
            },
        )
        assert overrides["driver_node_type_id"] == "r7g.4xlarge"

    def test_emits_people_instance_profile_arn_override(self):
        overrides = compute_validation_overrides(
            effective_prod={
                "aws_attributes": {
                    "instance_profile_arn": (
                        "{{ var.value.instance_profile_secret_arn_people }}"
                    ),
                },
            },
            mapped_worker="m7g.xlarge",
            mapped_driver=None,
            validation_resolved={
                "node_type_id": "m7g.xlarge",
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
            mapped_worker="m7g.xlarge",
            mapped_driver=None,
            validation_resolved={
                "node_type_id": "m7g.xlarge",
                "aws_attributes": {
                    "ebs_volume_size": 100,
                    "instance_profile_arn": "{{ var.value.instance_profile_arn }}",
                },
            },
        )
        assert overrides["aws_attributes"] == {"ebs_volume_size": 200}

    def test_photon_prod_emits_photon_without_normalization(self):
        overrides = compute_validation_overrides(
            effective_prod={"runtime_engine": "PHOTON"},
            mapped_worker="m7g.xlarge",
            mapped_driver=None,
            validation_resolved={"node_type_id": "m7g.xlarge"},
        )
        assert overrides.get("runtime_engine") == "PHOTON"

    def test_disable_photon_drops_runtime_engine_from_validation(self):
        overrides = compute_validation_overrides(
            effective_prod={"runtime_engine": "PHOTON"},
            mapped_worker="m7g.xlarge",
            mapped_driver=None,
            validation_resolved={"node_type_id": "m7g.xlarge"},
            recommended_runtime_engine="STANDARD",
        )
        # Normalizing Photon off must not carry PHOTON into the validation run;
        # the recommended preset already defaults to STANDARD.
        assert "runtime_engine" not in overrides

    def test_omits_aws_attributes_when_prod_matches_preset(self):
        overrides = compute_validation_overrides(
            effective_prod={
                "aws_attributes": {
                    "ebs_volume_size": 100,
                    "instance_profile_arn": "{{ var.value.instance_profile_arn }}",
                },
            },
            mapped_worker="m7g.xlarge",
            mapped_driver=None,
            validation_resolved={
                "node_type_id": "m7g.xlarge",
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
            mapped_worker="m7g.xlarge",
            mapped_driver="m7g.xlarge",
            validation_resolved={
                "node_type_id": "m7g.xlarge",
                "driver_node_type_id": "m7g.xlarge",
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
        assert mapped_worker == "m7g.2xlarge"
        assert mapped_driver == "m7g.xlarge"

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
        assert mapped_worker == "r7g.xlarge"
        assert mapped_driver == "r7g.8xlarge"

    def test_mapped_worker_rfleet_pool_resolves_to_memory(self):
        service = ConfigurationService()
        effective = service.get_config("databricks_16_4_rfleet_instance_cluster")
        mapped_worker, mapped_driver = _mapped_worker_and_driver(
            effective, "databricks_16_4_rfleet_instance_cluster"
        )
        assert mapped_worker == "r7g.xlarge"
        assert mapped_driver == "r7g.xlarge"

    def test_emr_preset_uses_master_node_type_id(self):
        resolved = ConfigurationService().get_config(
            "emr_7_12_consolidation_s_memory_cluster"
        )
        assert resolved.get("master_node_type_id") == "r6g.xlarge"
        assert "driver_node_type_id" not in resolved


class TestHasLoadSparkJob:
    @pytest.mark.parametrize(
        "workflow_type", ["qube_dimension", "qube_measure", "qube_metric"]
    )
    def test_qube_workflows_always_report_custom_spark_job(self, workflow_type):
        declaration = {
            "dag": {"name": "dimensions_chatbot_session_channel"},
            "workflow": {"type": workflow_type},
        }
        assert _has_load_spark_job(declaration) is True

    def test_query_delta_without_load_spark_job_is_false(self):
        declaration = {
            "dag": {"name": "core_aux_listing"},
            "workflow": {"type": "query_delta", "layer": "core"},
        }
        assert _has_load_spark_job(declaration) is False


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
        assert spec.custom_configurations["driver_node_type_id"] == "m7g.xlarge"
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

    def test_custom_cluster_resolving_to_prod_omits_validation(self):
        # hightouch_logs shape: prod custom_cluster maps to a consolidation preset
        # whose resolved spec equals prod, so the validation would validate nothing.
        declaration = {
            "dag": {"name": "hightouch_logs"},
            "workflow": {"type": "query_delta", "layer": "growth"},
            "cluster": {
                "type": "custom_cluster",
                "databricks_conn_id": "databricks_new",
                "custom_configurations": {
                    "driver_node_type_id": "r7g.2xlarge",
                    "node_type_id": "c7g.2xlarge",
                    "num_workers": 4,
                    "spark_version": "16.4.x-scala2.12",
                },
            },
        }
        spec = build_validation_cluster_spec(
            cluster_args=declaration["cluster"],
            declaration=declaration,
        )
        assert spec is None

    @pytest.mark.parametrize("dag_name", ["reverse_kyc", "enrich_search"])
    def test_excluded_dag_omits_validation(self, dag_name):
        declaration = {
            "dag": {"name": dag_name},
            "workflow": {
                "type": "load_access" if dag_name == "reverse_kyc" else "query",
                "layer": "reverse" if dag_name == "reverse_kyc" else "enrich",
                **(
                    {"load_spark_job": "load_reverse_kyc"}
                    if dag_name == "reverse_kyc"
                    else {}
                ),
            },
            "cluster": {
                "type": "databricks_13_3_med_general_cluster"
                if dag_name == "reverse_kyc"
                else "consolidation_l_general_cluster"
            },
        }
        spec = build_validation_cluster_spec(
            cluster_args=declaration["cluster"],
            declaration=declaration,
        )
        assert spec is None

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
        assert spec.custom_configurations["node_type_id"] == "m7gd.xlarge"
        # Photon no longer forces NVMe drivers: the mapped m7g.xlarge driver
        # matches the preset default and is stripped from the overrides.
        assert "driver_node_type_id" not in spec.custom_configurations
        assert spec.custom_configurations["runtime_engine"] == "PHOTON"
        assert spec.custom_configurations["num_workers"] == 3

    def test_explicit_nvme_without_photon_validation_overrides(self):
        # A legacy worker (r5) migrates to graviton while an explicit NVMe driver
        # (r6gd) is preserved without a Photon upgrade -- a real validation, not a
        # no-op, because prod and the mapped validation resolve differently.
        declaration = {
            "dag": {"name": "enrich_nvme_only"},
            "workflow": {"type": "query_delta", "layer": "enrich"},
            "cluster": {
                "type": "custom_cluster",
                "databricks_conn_id": "databricks_new_env",
                "custom_configurations": {
                    "driver_node_type_id": "r7gd.4xlarge",
                    "node_type_id": "r5.4xlarge",
                    "num_workers": 5,
                },
            },
        }
        spec = build_validation_cluster_spec(
            cluster_args=declaration["cluster"],
            declaration=declaration,
        )
        assert spec is not None
        assert spec.cluster_type == "consolidation_l_memory_cluster"
        assert spec.custom_configurations["driver_node_type_id"] == "r7gd.4xlarge"
        assert "node_type_id" not in spec.custom_configurations
        assert "runtime_engine" not in spec.custom_configurations
        assert spec.custom_configurations["num_workers"] == 5

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
        # Legacy NVMe c5d worker keeps local NVMe on Graviton (c7gd) and is a
        # real override against the preset's non-NVMe default.
        assert spec.custom_configurations["node_type_id"] == "c7gd.8xlarge"
        assert spec.custom_configurations["driver_node_type_id"] == "m7g.2xlarge"
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
        assert spec.custom_configurations["node_type_id"] == "c7g.12xlarge"
        assert spec.custom_configurations["driver_node_type_id"] == "r7g.2xlarge"
        assert spec.custom_configurations["num_workers"] == 8

    def test_sedona_preset_emits_preset_only_init_scripts(self):
        declaration = {
            "dag": {"name": "ebdb_location"},
            "workflow": {"type": "query_delta", "layer": "enrich"},
            "cluster": {
                "type": "custom_cluster_with_sedona",
                "custom_configurations": {
                    # Legacy m5 types so the consolidation mapping is a real
                    # migration (not a no-op) while sedona init scripts persist.
                    "driver_node_type_id": "m5.xlarge",
                    "node_type_id": "m5.xlarge",
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


class TestBuildValidationClusterSpecWonkaRouting:
    @staticmethod
    def _wonka_declaration() -> dict:
        return {
            "dag": {"name": "house_main"},
            "workflow": {
                "type": "wonka",
                "layer": "wonka",
                "wonka_config": {"name": "house_main"},
            },
            "cluster": {
                "type": "wonka_cluster",
                "custom_configurations": {
                    "spark_version": "15.4.x-scala2.12",
                    "driver_node_type_id": "c5a.4xlarge",
                    "node_type_id": "r5a.8xlarge",
                    "num_workers": 2,
                },
            },
        }

    def test_wonka_cluster_routes_to_wonka_preset_without_runtime_boilerplate(self):
        declaration = self._wonka_declaration()
        spec = build_validation_cluster_spec(
            cluster_args=declaration["cluster"],
            declaration=declaration,
        )
        assert spec is not None
        assert spec.cluster_type.startswith("wonka_consolidation_")
        # The wonka presets carry the wonka runtime; the generated block must
        # not restate it as per-job overrides.
        custom = spec.custom_configurations or {}
        assert "spark_env_vars" not in custom
        assert "init_scripts" not in custom
        assert "access_control_list" not in custom

    def test_non_wonka_cluster_never_routes_to_wonka_preset(self):
        # Same topology and 15.4 runtime as a wonka prod job — the closest
        # catalog entry by spark_version is the wonka twin — but non-wonka
        # DAGs must only ever match the generic pool.
        declaration = {
            "dag": {"name": "lookalike_custom"},
            "workflow": {"type": "query_delta", "layer": "enrich"},
            "cluster": {
                "type": "custom_cluster",
                "custom_configurations": {
                    "spark_version": "15.4.x-scala2.12",
                    "driver_node_type_id": "c5a.4xlarge",
                    "node_type_id": "r5a.8xlarge",
                    "num_workers": 2,
                },
            },
        }
        spec = build_validation_cluster_spec(
            cluster_args=declaration["cluster"],
            declaration=declaration,
        )
        assert spec is not None
        assert spec.cluster_type == "consolidation_xl_memory_cluster"


class TestStripRedundantPresetDefaultOverrides:
    def test_strip_worker_driver_and_num_workers_echoes(self):
        cluster_args = {
            "type": "consolidation_xs_general_cluster",
            "custom_configurations": {
                "node_type_id": "m7g.large",
                "driver_node_type_id": "m7g.xlarge",
                "num_workers": 2,
            },
        }
        stripped = strip_redundant_preset_default_overrides(
            cluster_args, ConfigurationService()
        )
        custom = stripped["custom_configurations"]
        assert "node_type_id" not in custom
        assert "num_workers" not in custom
        assert custom["driver_node_type_id"] == "m7g.xlarge"

    def test_strip_redundant_driver_when_equal_to_preset(self):
        cluster_args = {
            "type": "consolidation_xs_general_cluster",
            "custom_configurations": {
                "driver_node_type_id": "m7g.large",
                "node_type_id": "m7g.xlarge",
            },
        }
        stripped = strip_redundant_preset_default_overrides(
            cluster_args, ConfigurationService()
        )
        custom = stripped["custom_configurations"]
        assert "driver_node_type_id" not in custom
        assert custom["node_type_id"] == "m7g.xlarge"

    def test_normalize_strips_redundant_after_mapping(self):
        cluster_args = {
            "type": "consolidation_xs_general_cluster",
            "custom_configurations": {
                "node_type_id": "m7g.large",
                "driver_node_type_id": "m7g.xlarge",
                "num_workers": 2,
            },
        }
        normalized = normalize_databricks_cluster_topology(
            cluster_args, ConfigurationService()
        )
        custom = normalized["custom_configurations"]
        assert "node_type_id" not in custom
        assert "num_workers" not in custom
        assert custom["driver_node_type_id"] == "m7g.xlarge"


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
        assert custom["driver_node_type_id"] == "m7g.xlarge"
        assert custom["node_type_id"] == "m7g.large"
        assert custom["num_workers"] == 1

    def test_maps_consolidation_worker_override_to_graviton(self):
        cluster_args = {
            "type": "consolidation_m_general_cluster",
            "custom_configurations": {
                "driver_node_type_id": "m7g.xlarge",
                "node_type_id": "m5a.2xlarge",
            },
        }
        normalized = normalize_databricks_cluster_topology(
            cluster_args, ConfigurationService()
        )
        custom = normalized["custom_configurations"]
        assert custom["driver_node_type_id"] == "m7g.xlarge"
        assert "node_type_id" not in custom

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
        # Driver never inherits NVMe; the legacy NVMe r5d worker keeps it.
        assert custom["driver_node_type_id"] == "m7g.xlarge"
        assert custom["node_type_id"] == "r7gd.2xlarge"

    def test_preserves_explicit_nvme_without_photon(self):
        cluster_args = {
            "type": "consolidation_l_memory_cluster",
            "custom_configurations": {
                "driver_node_type_id": "r7gd.4xlarge",
                "node_type_id": "r7gd.4xlarge",
                "num_workers": 5,
            },
        }
        normalized = normalize_databricks_cluster_topology(
            cluster_args, ConfigurationService()
        )
        custom = normalized["custom_configurations"]
        assert custom["driver_node_type_id"] == "r7gd.4xlarge"
        assert custom["node_type_id"] == "r7gd.4xlarge"
        assert "runtime_engine" not in custom

    def test_legacy_r5d_without_photon_maps_to_nvme_graviton(self):
        cluster_args = {
            "type": "consolidation_l_memory_cluster",
            "custom_configurations": {
                "driver_node_type_id": "r5d.4xlarge",
                "node_type_id": "r5d.4xlarge",
            },
        }
        normalized = normalize_databricks_cluster_topology(
            cluster_args, ConfigurationService()
        )
        custom = normalized["custom_configurations"]
        # Legacy NVMe workers keep local NVMe even without Photon; the driver
        # maps to non-NVMe r7g.4xlarge, which equals the preset default and is
        # stripped.
        assert custom["node_type_id"] == "r7gd.4xlarge"
        assert "driver_node_type_id" not in custom

    def test_photon_does_not_upgrade_explicit_graviton_to_nvme(self):
        cluster_args = {
            "type": "consolidation_m_memory_cluster",
            "custom_configurations": {
                "runtime_engine": "PHOTON",
                "driver_node_type_id": "r7g.xlarge",
                "node_type_id": "r7g.xlarge",
                "num_workers": 3,
            },
        }
        normalized = normalize_databricks_cluster_topology(
            cluster_args, ConfigurationService()
        )
        custom = normalized["custom_configurations"]
        assert custom["driver_node_type_id"] == "r7g.xlarge"
        assert custom["node_type_id"] == "r7g.xlarge"
        assert custom["runtime_engine"] == "PHOTON"

    def test_photon_legacy_d_type_worker_maps_to_nvme_driver_stays_non_nvme(self):
        cluster_args = {
            "type": "consolidation_s_general_cluster",
            "custom_configurations": {
                "runtime_engine": "PHOTON",
                "driver_node_type_id": "m5d.xlarge",
                "node_type_id": "m5d.xlarge",
            },
        }
        normalized = normalize_databricks_cluster_topology(
            cluster_args, ConfigurationService()
        )
        custom = normalized["custom_configurations"]
        # The worker keeps NVMe (m7gd); the driver maps to non-NVMe m7g.xlarge,
        # which equals the preset default and is stripped.
        assert custom["node_type_id"] == "m7gd.xlarge"
        assert "driver_node_type_id" not in custom

    def test_legacy_nvme_worker_and_driver_without_photon(self):
        cluster_args = {
            "type": "custom_cluster",
            "custom_configurations": {
                "node_type_id": "c6id.12xlarge",
                "driver_node_type_id": "c6id.4xlarge",
            },
        }
        normalized = normalize_databricks_cluster_topology(
            cluster_args, ConfigurationService()
        )
        custom = normalized["custom_configurations"]
        # Legacy NVMe x86 workers map to *gd without Photon; drivers never
        # inherit NVMe unless prod already pinned an explicit *gd driver.
        assert custom["node_type_id"] == "c7gd.12xlarge"
        assert custom["driver_node_type_id"] == "c7g.4xlarge"

    def test_legacy_m5d_worker_maps_to_nvme_graviton(self):
        cluster_args = {
            "type": "custom_cluster",
            "custom_configurations": {
                "node_type_id": "m5d.2xlarge",
            },
        }
        normalized = normalize_databricks_cluster_topology(
            cluster_args, ConfigurationService()
        )
        assert normalized["custom_configurations"]["node_type_id"] == "m7gd.2xlarge"

    def test_non_nvme_legacy_worker_maps_to_non_nvme_graviton(self):
        cluster_args = {
            "type": "custom_cluster",
            "custom_configurations": {
                "node_type_id": "r5a.8xlarge",
            },
        }
        normalized = normalize_databricks_cluster_topology(
            cluster_args, ConfigurationService()
        )
        assert normalized["custom_configurations"]["node_type_id"] == "r7g.8xlarge"


class TestBuildRightsizingValidationClusterSpec:
    def test_general_to_memory_single_node_omits_preset_defaults(self):
        declaration = {
            "dag": {"name": "enrich_semrush_classified"},
            "workflow": {"type": "query_delta", "layer": "enrich"},
        }
        prod_cluster_args = {
            "type": "consolidation_xs_general_single_node_cluster",
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
        spec = build_rightsizing_validation_cluster_spec(
            prod_cluster_args=prod_cluster_args,
            declaration=declaration,
            recommended_preset="consolidation_xs_memory_single_node_cluster",
            recommended_num_workers=0,
            recommended_driver_node_type="r7g.large",
        )

        assert spec is not None
        assert spec.cluster_type == "consolidation_xs_memory_single_node_cluster"
        assert spec.databricks_conn_id == "databricks_new_env"
        assert "num_workers" not in spec.custom_configurations
        assert "node_type_id" not in spec.custom_configurations
        assert "driver_node_type_id" not in spec.custom_configurations
        assert spec.custom_configurations == {}

    def test_larger_single_node_driver_override_only(self):
        declaration = {
            "dag": {"name": "ebdb_visit_fast_lane"},
            "workflow": {"type": "query_delta", "layer": "enrich"},
        }
        prod_cluster_args = {
            "type": "consolidation_m_memory_cluster",
            "databricks_conn_id": "databricks_new",
        }
        spec = build_rightsizing_validation_cluster_spec(
            prod_cluster_args=prod_cluster_args,
            declaration=declaration,
            recommended_preset="consolidation_m_memory_single_node_cluster",
            recommended_num_workers=0,
            recommended_driver_node_type="r7g.4xlarge",
        )

        assert spec is not None
        assert spec.custom_configurations == {
            "driver_node_type_id": "r7g.4xlarge",
        }

    def test_keep_multi_num_workers_override_only(self):
        declaration = {
            "dag": {"name": "klefki"},
            "workflow": {"type": "query_delta", "layer": "enrich"},
        }
        prod_cluster_args = {
            "type": "consolidation_xs_memory_cluster",
            "databricks_conn_id": "databricks_new",
            "custom_configurations": {
                "num_workers": 4,
                "driver_node_type_id": "r7g.2xlarge",
            },
        }
        spec = build_rightsizing_validation_cluster_spec(
            prod_cluster_args=prod_cluster_args,
            declaration=declaration,
            recommended_preset="consolidation_xs_memory_cluster",
            recommended_num_workers=3,
            recommended_driver_node_type="r7g.2xlarge",
            recommended_worker_node_type="r7g.large",
        )

        assert spec is not None
        assert spec.custom_configurations.get("num_workers") == 3
        assert "node_type_id" not in spec.custom_configurations

    def test_keep_multi_same_node_retarget_preserves_worker_override(self):
        """Multi-node retarget where driver and worker map to the same newer-gen
        node must keep the worker node_type_id. Dropping it (the single-node pop)
        would silently revert the worker to the preset default."""
        declaration = {
            "dag": {"name": "meetcall"},
            "workflow": {"type": "query_delta", "layer": "enrich"},
        }
        prod_cluster_args = {
            "type": "consolidation_xs_memory_cluster",
            "databricks_conn_id": "databricks_new",
            "custom_configurations": {
                "num_workers": 3,
                "driver_node_type_id": "m7g.xlarge",
            },
        }
        spec = build_rightsizing_validation_cluster_spec(
            prod_cluster_args=prod_cluster_args,
            declaration=declaration,
            recommended_preset="consolidation_xs_memory_cluster",
            recommended_num_workers=3,
            recommended_driver_node_type="r7g.xlarge",
            recommended_worker_node_type="r7g.xlarge",
        )

        assert spec is not None
        assert spec.custom_configurations["node_type_id"] == "r7g.xlarge"
        assert spec.custom_configurations["num_workers"] == 3

    def test_returns_none_for_emr_prod_cluster(self):
        prod_cluster_args = {
            "type": "emr_7_12_consolidation_m_memory_cluster",
            "custom_configurations": {
                "core_nodes": {"instance_count": 1},
                "task_nodes": {"instance_count": 2},
            },
        }
        spec = build_rightsizing_validation_cluster_spec(
            prod_cluster_args=prod_cluster_args,
            declaration={"dag": {"name": "dw_analytical_costs"}},
            recommended_preset="consolidation_s_general_cluster",
            recommended_driver_node_type="r7g.2xlarge",
            recommended_worker_node_type="m7g.xlarge",
        )

        assert spec is None


class TestEmrConsolidationSparkDefaults:
    def test_emr_consolidation_preset_keeps_hive_catalog_defaults(self):
        service = ConfigurationService()
        preset = service.get_config(
            "emr_7_12_consolidation_xl_memory_single_node_cluster"
        )

        spark_conf = preset["spark_conf"]
        assert spark_conf["spark.sql.catalogImplementation"] == "hive"
        assert spark_conf["spark.sql.legacy.createHiveTableByDefault"] == "true"
        assert spark_conf["spark.driverEnv.SPARK_RUNTIME"] == "emr"

    def test_cluster_custom_spark_conf_overrides_without_dropping_defaults(self):
        service = ConfigurationService()
        cluster_args = {
            "type": "emr_7_12_consolidation_xl_memory_single_node_cluster",
            "custom_configurations": {
                "spark_conf": {
                    "spark.driver.memory": "8g",
                    "spark.driver.cores": "4",
                    "spark.executor.memory": "24g",
                    "spark.executor.cores": "4",
                    "spark.dynamicAllocation.minExecutors": "2",
                    "spark.dynamicAllocation.maxExecutors": "24",
                }
            },
        }
        effective = merge_cluster_configuration(cluster_args, service)
        spark_conf = effective["spark_conf"]

        assert spark_conf["spark.sql.catalogImplementation"] == "hive"
        assert spark_conf["spark.driverEnv.SPARK_RUNTIME"] == "emr"
        assert spark_conf["spark.driver.memory"] == "8g"
        assert spark_conf["spark.dynamicAllocation.maxExecutors"] == "24"

    def test_empty_custom_spark_conf_preserves_preset_defaults(self):
        """``spark_conf: {}`` means "no extra conf", not "drop the preset's conf".

        HierarchicalConf._deep_update only recurses into truthy mappings, so an
        empty dict used to replace the whole block — stripping
        spark.sql.catalogImplementation and every sizing override, which made
        Glue-backed JSON/Parquet tables raise TABLE_OR_VIEW_NOT_FOUND on EMR.
        """
        service = ConfigurationService()
        cluster_args = {
            "type": "emr_7_12_consolidation_l_memory_fleet_cluster",
            "custom_configurations": {"spark_conf": {}},
        }
        effective = merge_cluster_configuration(cluster_args, service)
        spark_conf = effective["spark_conf"]

        assert spark_conf["spark.sql.catalogImplementation"] == "hive"
        assert spark_conf["spark.driverEnv.SPARK_RUNTIME"] == "emr"
        assert "spark.executor.memory" in spark_conf


class TestEmrValidationClustersResolveHiveCatalog:
    """Every declared EMR validation cluster must resolve a Hive-backed catalog.

    Without ``spark.sql.catalogImplementation: hive`` in the effective spark_conf,
    Spark cannot resolve plain Hive-SerDe (JSON/Parquet) Glue tables — Delta tables
    still work via delta-defaults, so the gap surfaces only on non-Delta reads.
    """

    @staticmethod
    def _emr_validation_cluster_args():
        repo_root = Path(__file__).resolve().parents[6]
        for path in sorted((repo_root / "dags").glob("*/*/*_cluster.yml")):
            declaration = yaml.safe_load(path.read_text()) or {}
            prod_cluster = declaration.get("cluster") or {}
            validation_cluster = (declaration.get("validation") or {}).get("cluster")
            if not validation_cluster:
                continue
            if not str(validation_cluster.get("type", "")).startswith("emr_"):
                continue
            yield path, merge_validation_cluster_args(prod_cluster, validation_cluster)

    def test_every_emr_validation_cluster_keeps_hive_catalog_and_sizing(self):
        service = ConfigurationService()
        offenders = []
        checked = 0

        for path, cluster_args in self._emr_validation_cluster_args():
            checked += 1
            spark_conf = (
                merge_cluster_configuration(cluster_args, service).get("spark_conf")
                or {}
            )
            missing = [
                key
                for key in (
                    "spark.sql.catalogImplementation",
                    "spark.driverEnv.SPARK_RUNTIME",
                    "spark.executor.memory",
                )
                if key not in spark_conf
            ]
            if missing or spark_conf.get("spark.sql.catalogImplementation") != "hive":
                offenders.append(f"{path.name}: missing={missing}")

        assert checked > 0, "no EMR validation clusters discovered"
        assert not offenders, (
            "EMR validation clusters with a broken catalog:\n" + "\n".join(offenders)
        )

    def test_custom_configurations_never_drop_preset_spark_conf_keys(self):
        """``spark_conf`` must always *merge* with the preset anchor, never replace it.

        ``custom_configurations.spark_conf`` may override a preset key or add a new
        one, but it must never remove one — the anchors (``emr_spark_base`` plus the
        sizing anchor) are the floor for every EMR cluster.
        """
        service = ConfigurationService()
        offenders = []

        for path, cluster_args in self._emr_validation_cluster_args():
            preset_keys = set(
                service.get_config(cluster_args["type"]).get("spark_conf") or {}
            )
            effective_keys = set(
                merge_cluster_configuration(cluster_args, service).get("spark_conf")
                or {}
            )
            dropped = preset_keys - effective_keys
            if dropped:
                offenders.append(f"{path.name}: dropped={sorted(dropped)}")

        assert not offenders, (
            "custom_configurations dropped preset spark_conf keys:\n"
            + "\n".join(offenders)
        )


def _map_dbr_instance_to_emr(instance_type: str) -> str:
    """Prod DBR gen7 → EMR gen6 Graviton."""
    for gen7, gen6 in (("m7g", "m6g"), ("r7g", "r6g"), ("c7g", "c6g")):
        instance_type = instance_type.replace(gen7, gen6)
    return instance_type


def _emr_instance_type(dbr_instance_type: str) -> str:
    """Map DBR instance type to EMR, enforcing xlarge as the minimum size."""
    mapped = _map_dbr_instance_to_emr(dbr_instance_type)
    family, size = mapped.rsplit(".", 1)
    if size == "large":
        return f"{family}.xlarge"
    return mapped


def _emr_consolidation_preset_names():
    tiers = ("xs", "s", "m", "l", "xl")
    families = ("compute", "general", "memory")
    presets = [
        f"emr_7_12_consolidation_{tier}_{family}_cluster"
        for tier in tiers
        for family in families
    ]
    for tier in tiers:
        for family in ("general", "memory"):
            presets.append(
                f"emr_7_12_consolidation_{tier}_{family}_single_node_cluster"
            )
    return presets


def _dbr_counterpart(emr_preset: str) -> str:
    suffix = emr_preset.removeprefix("emr_7_12_")
    return suffix


def _parse_memory_gib(value: str) -> float:
    normalized = value.strip().lower()
    if normalized.endswith("g"):
        return float(normalized[:-1])
    if normalized.endswith("m"):
        return float(normalized[:-1]) / 1024
    raise ValueError(f"unsupported memory value: {value}")


# Graviton instance RAM (GiB) for master budget checks.
_INSTANCE_RAM_GIB = {
    "c6g.large": 4,
    "c6g.xlarge": 8,
    "c6g.2xlarge": 16,
    "c6g.4xlarge": 32,
    "c6g.8xlarge": 64,
    "c7g.large": 4,
    "c7g.xlarge": 8,
    "c7g.2xlarge": 16,
    "c7g.4xlarge": 32,
    "c7g.8xlarge": 64,
    "m6g.large": 8,
    "m6g.xlarge": 16,
    "m6g.2xlarge": 32,
    "m6g.4xlarge": 64,
    "m6g.8xlarge": 128,
    "m7g.large": 8,
    "m7g.xlarge": 16,
    "m7g.2xlarge": 32,
    "m7g.4xlarge": 64,
    "m7g.8xlarge": 128,
    "r6g.large": 16,
    "r6g.xlarge": 32,
    "r6g.2xlarge": 64,
    "r6g.4xlarge": 128,
    "r6g.8xlarge": 256,
    "r7g.large": 16,
    "r7g.xlarge": 32,
    "r7g.2xlarge": 64,
    "r7g.4xlarge": 128,
    "r7g.8xlarge": 256,
}


class TestEmrWorkerCoreTaskSplit:
    @pytest.mark.parametrize(
        "total_workers,expected_core,expected_task",
        [
            (0, 0, 0),
            (1, 1, 0),
            (2, 2, 0),
            (3, 2, 1),
            (4, 2, 2),
            (5, 2, 3),
        ],
    )
    def test_split(self, total_workers, expected_core, expected_task):
        from scripts.ci_cd.airflow_dag_builder.cluster_validation_mapping import (
            emr_worker_core_task_split,
        )

        assert emr_worker_core_task_split(total_workers) == (
            expected_core,
            expected_task,
        )


class TestMapInstanceTypeToEmrGen6:
    @pytest.mark.parametrize(
        "raw,expected",
        [
            ("m7g.xlarge", "m6g.xlarge"),
            ("r7g.2xlarge", "r6g.2xlarge"),
            ("c7g.4xlarge", "c6g.4xlarge"),
            ("m7a.xlarge", "m6g.xlarge"),
            ("r7a.2xlarge", "r6g.2xlarge"),
            ("m5a.2xlarge", "m6g.2xlarge"),
        ],
    )
    def test_maps_to_gen6_graviton(self, raw, expected):
        from scripts.ci_cd.airflow_dag_builder.cluster_validation_mapping import (
            map_instance_type_to_emr_gen6,
        )

        assert map_instance_type_to_emr_gen6(raw) == expected


class TestEmrConsolidationDbrParity:
    @pytest.mark.parametrize("emr_preset", _emr_consolidation_preset_names())
    def test_topology_matches_databricks_consolidation_preset(self, emr_preset):
        service = ConfigurationService()
        dbr_preset = service.get_config(_dbr_counterpart(emr_preset))
        emr = service.get_config(emr_preset)

        expected_master = _emr_instance_type(dbr_preset["driver_node_type_id"])
        assert emr.get("master_node_type_id") == expected_master

        num_workers = dbr_preset["num_workers"]
        if num_workers == 0:
            assert emr["core_nodes"]["instance_count"] == 0
            task_nodes = emr.get("task_nodes")
            assert task_nodes is None or task_nodes.get("instance_count", 0) == 0
            return

        expected_worker = _emr_instance_type(dbr_preset["node_type_id"])
        assert emr["core_nodes"]["node_type_id"] == expected_worker
        if num_workers == 2:
            assert emr["core_nodes"]["instance_count"] == 2
            assert emr["task_nodes"]["node_type_id"] == expected_worker
            assert emr["task_nodes"]["instance_count"] == 0
        elif num_workers == 1:
            assert emr["core_nodes"]["instance_count"] == 1
            task_nodes = emr.get("task_nodes")
            assert task_nodes is None or task_nodes.get("instance_count", 0) == 0
        else:
            assert emr.get("task_nodes") is None

    @pytest.mark.parametrize("emr_preset", _emr_consolidation_preset_names())
    def test_consolidation_core_on_demand_with_spot_tasks(self, emr_preset):
        emr = ConfigurationService().get_config(emr_preset)
        aws = emr["aws_attributes"]
        if emr_preset.endswith("_single_node_cluster"):
            return
        assert aws["availability"] == "ON_DEMAND"
        task_count = (emr.get("task_nodes") or {}).get("instance_count", 0)
        if task_count > 0:
            assert aws["task_availability"] == "SPOT"


class TestEmrSmallGeneralSingleNodeTopology:
    def test_small_general_2xlarge_single_node_is_master_only(self):
        service = ConfigurationService()
        dbr = service.get_config(
            "databricks_16_4_small_general_fleet_2xlarge_single_node"
        )
        emr = service.get_config("emr_7_12_small_general_2xlarge_single_node_cluster")

        assert dbr["num_workers"] == 0
        assert emr["core_nodes"]["instance_count"] == 0
        task_nodes = emr.get("task_nodes")
        assert task_nodes is None or task_nodes.get("instance_count", 0) == 0


class TestEmrConsolidationMasterMemorySizing:
    @pytest.mark.parametrize(
        "emr_preset,yarn_am,driver",
        [
            ("emr_7_12_consolidation_xs_compute_cluster", "512m", "1g"),
            ("emr_7_12_consolidation_s_general_cluster", "2g", "6g"),
            ("emr_7_12_consolidation_l_memory_cluster", "4g", "12g"),
            ("emr_7_12_consolidation_xl_memory_cluster", "6g", "16g"),
        ],
    )
    def test_tier_master_memory_not_flat_eight_gb(self, emr_preset, yarn_am, driver):
        spark_conf = ConfigurationService().get_config(emr_preset)["spark_conf"]
        assert spark_conf["spark.yarn.am.memory"] == yarn_am
        assert spark_conf["spark.driver.memory"] == driver
        assert spark_conf["spark.yarn.am.memory"] != "8g" or emr_preset.endswith(
            "_general_cluster"
        )

    @pytest.mark.parametrize("emr_preset", _emr_consolidation_preset_names())
    def test_master_memory_within_instance_budget(self, emr_preset):
        if emr_preset.endswith("_single_node_cluster"):
            pytest.skip(
                "single-node runs executors on master; budget checked separately"
            )
        emr = ConfigurationService().get_config(emr_preset)
        spark_conf = emr["spark_conf"]
        master_type = emr["master_node_type_id"]
        instance_ram = _INSTANCE_RAM_GIB[master_type]
        used_gib = (
            _parse_memory_gib(spark_conf["spark.driver.memory"])
            + _parse_memory_gib(spark_conf["spark.driver.memoryOverhead"])
            + _parse_memory_gib(spark_conf["spark.yarn.am.memory"])
        )
        assert used_gib <= instance_ram * 0.7

    @pytest.mark.parametrize(
        "emr_preset",
        [
            p
            for p in _emr_consolidation_preset_names()
            if p.endswith("_single_node_cluster")
        ],
    )
    def test_single_node_total_memory_within_instance_budget(self, emr_preset):
        emr = ConfigurationService().get_config(emr_preset)
        spark_conf = emr["spark_conf"]
        master_type = emr["master_node_type_id"]
        instance_ram = _INSTANCE_RAM_GIB[master_type]
        used_gib = (
            _parse_memory_gib(spark_conf["spark.driver.memory"])
            + _parse_memory_gib(spark_conf["spark.driver.memoryOverhead"])
            + _parse_memory_gib(spark_conf["spark.yarn.am.memory"])
            + _parse_memory_gib(spark_conf["spark.executor.memory"])
            + _parse_memory_gib(spark_conf["spark.executor.memoryOverhead"])
        )
        assert used_gib <= instance_ram * 0.875
        assert spark_conf["spark.dynamicAllocation.maxExecutors"] == "1"
        assert spark_conf["spark.executor.instances"] == "1"
