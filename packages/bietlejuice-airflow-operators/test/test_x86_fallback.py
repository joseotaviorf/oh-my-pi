import pytest
from emr_plugin.x86_fallback import (
    GRAVITON_ALLOW_KEY,
    X86_FALLBACK_ENV_VAR,
    apply_x86_fallback,
    to_x86_instance_type,
    x86_fallback_enabled,
)


@pytest.mark.parametrize(
    "graviton,expected",
    [
        ("m6g.large", "m6a.large"),
        ("m6g.xlarge", "m6a.xlarge"),
        ("m6g.2xlarge", "m6a.2xlarge"),
        ("m6g.4xlarge", "m6a.4xlarge"),
        ("m6g.8xlarge", "m6a.8xlarge"),
        ("m7g.large", "m7a.large"),
        ("m7g.xlarge", "m7a.xlarge"),
        ("m7g.2xlarge", "m7a.2xlarge"),
        ("m7g.12xlarge", "m7a.12xlarge"),
        ("r6g.xlarge", "r6a.xlarge"),
        ("r6g.12xlarge", "r6a.12xlarge"),
        ("r7g.large", "r7a.large"),
        ("r7g.8xlarge", "r7a.8xlarge"),
        ("c6g.2xlarge", "c6a.2xlarge"),
        ("c7g.8xlarge", "c7a.8xlarge"),
    ],
)
def test_graviton_maps_to_amd_keeping_size(graviton, expected):
    # act / assert
    assert to_x86_instance_type(graviton) == expected


@pytest.mark.parametrize(
    "graviton,expected",
    [
        ("m6gd.xlarge", "m6id.xlarge"),
        ("m6gd.4xlarge", "m6id.4xlarge"),
        ("m7gd.large", "m6id.large"),
        ("m7gd.8xlarge", "m6id.8xlarge"),
        ("r6gd.8xlarge", "r6id.8xlarge"),
        ("r7gd.2xlarge", "r6id.2xlarge"),
        ("c6gd.xlarge", "c6id.xlarge"),
        ("c7gd.4xlarge", "c6id.4xlarge"),
    ],
)
def test_nvme_graviton_maps_to_intel_d_family(graviton, expected):
    # AMD has no gen-6/7 local-NVMe family, so `gd` falls back to Intel `id`.
    assert to_x86_instance_type(graviton) == expected


@pytest.mark.parametrize(
    "instance_type",
    [
        "m5.xlarge",
        "m5a.large",
        "m6a.2xlarge",
        "r5d.large",
        "r6i.xlarge",
        "r6id.8xlarge",
        "c5a.2xlarge",
        "i3.xlarge",
        "",
    ],
)
def test_non_graviton_passes_through_unchanged(instance_type):
    assert to_x86_instance_type(instance_type) == instance_type


@pytest.mark.parametrize(
    "instance_type", ["i4g.xlarge", "x2gd.2xlarge", "g5g.xlarge", "im4gn.large"]
)
def test_unmapped_graviton_families_pass_through_unchanged(instance_type):
    # Storage/GPU Graviton families have no like-for-like x86 counterpart and
    # are unused here; leaving them alone beats guessing a wrong replacement.
    assert to_x86_instance_type(instance_type) == instance_type


@pytest.mark.parametrize("value", [None, 42, ["r6g.xlarge"]])
def test_non_string_values_pass_through_unchanged(value):
    assert to_x86_instance_type(value) == value


@pytest.mark.parametrize(
    "instance_type", ["m6g.xlarge", "r7gd.2xlarge", "c7g.8xlarge", "m5.xlarge"]
)
def test_mapping_is_idempotent(instance_type):
    # translate() runs at DAG-parse and at task-execute time on the same config.
    once = to_x86_instance_type(instance_type)
    assert to_x86_instance_type(once) == once


def test_apply_rewrites_every_instance_type_key():
    # arrange
    cfg = {
        "master_node_type_id": "m7g.xlarge",
        "driver_node_type_id": "m6g.xlarge",
        "node_type_id": "r6g.2xlarge",
        "task_node_type_id": "r7g.2xlarge",
        "core_nodes": {"node_type_id": "c6g.4xlarge", "instance_count": 2},
        "task_nodes": {"node_type_id": "c7g.4xlarge", "instance_count": 1},
    }

    # act
    apply_x86_fallback(cfg)

    # assert
    assert cfg["master_node_type_id"] == "m7a.xlarge"
    assert cfg["driver_node_type_id"] == "m6a.xlarge"
    assert cfg["node_type_id"] == "r6a.2xlarge"
    assert cfg["task_node_type_id"] == "r7a.2xlarge"
    assert cfg["core_nodes"]["node_type_id"] == "c6a.4xlarge"
    assert cfg["task_nodes"]["node_type_id"] == "c7a.4xlarge"


def test_apply_rewrites_fleet_instance_type_lists():
    # arrange
    cfg = {
        "master_node_type_id": "r6g.xlarge",
        "core_nodes": {
            "instance_types": ["r6g.xlarge", "r7g.xlarge", "r6i.xlarge"],
            "target_on_demand": 1,
            "target_spot": 0,
        },
        "task_nodes": {
            "instance_types": ["m6g.2xlarge", "m7g.2xlarge"],
            "target_on_demand": 0,
            "target_spot": 2,
        },
    }

    # act
    apply_x86_fallback(cfg)

    # assert
    assert cfg["master_node_type_id"] == "r6a.xlarge"
    assert cfg["core_nodes"]["instance_types"] == [
        "r6a.xlarge",
        "r7a.xlarge",
        "r6i.xlarge",
    ]
    assert cfg["task_nodes"]["instance_types"] == ["m6a.2xlarge", "m7a.2xlarge"]


def test_fleet_list_deduplicates_collisions_preserving_order():
    # arrange: gen-6 and gen-7 NVMe Graviton both collapse onto m6id.
    cfg = {
        "core_nodes": {"instance_types": ["m6gd.4xlarge", "m7gd.4xlarge"]},
        "task_nodes": {"instance_types": ["r7gd.2xlarge", "r6id.2xlarge"]},
    }

    # act
    apply_x86_fallback(cfg)

    # assert
    assert cfg["core_nodes"]["instance_types"] == ["m6id.4xlarge"]
    assert cfg["task_nodes"]["instance_types"] == ["r6id.2xlarge"]


def test_apply_leaves_unrelated_keys_untouched():
    # arrange
    cfg = {
        "cluster_name": "test",
        "spark_version": "emr-7.12.0",
        "master_node_type_id": "r6g.xlarge",
        "spark_conf": {"spark.executor.memory": "20g"},
        "core_nodes": {"instance_types": ["r6g.xlarge"], "target_on_demand": 1},
    }

    # act
    apply_x86_fallback(cfg)

    # assert
    assert cfg["cluster_name"] == "test"
    assert cfg["spark_version"] == "emr-7.12.0"
    assert cfg["spark_conf"] == {"spark.executor.memory": "20g"}
    assert cfg["core_nodes"]["target_on_demand"] == 1


def test_apply_tolerates_missing_and_non_dict_node_blocks():
    # arrange
    cfg = {"master_node_type_id": "m6g.xlarge", "core_nodes": None, "task_nodes": []}

    # act
    apply_x86_fallback(cfg)

    # assert
    assert cfg["master_node_type_id"] == "m6a.xlarge"
    assert cfg["core_nodes"] is None
    assert cfg["task_nodes"] == []


@pytest.mark.parametrize("disabled_value", ["0", "false", "FALSE", "no", "off", ""])
def test_env_var_disables_the_fallback(monkeypatch, disabled_value):
    # arrange
    monkeypatch.setenv(X86_FALLBACK_ENV_VAR, disabled_value)
    cfg = {
        "master_node_type_id": "r6g.xlarge",
        "core_nodes": {"instance_types": ["r6g.xlarge"]},
    }

    # act
    apply_x86_fallback(cfg)

    # assert
    assert not x86_fallback_enabled()
    assert cfg["master_node_type_id"] == "r6g.xlarge"
    assert cfg["core_nodes"]["instance_types"] == ["r6g.xlarge"]


@pytest.mark.parametrize("enabled_value", ["1", "true", "TRUE", "yes", "on"])
def test_env_var_explicitly_enables_the_fallback(monkeypatch, enabled_value):
    # arrange
    monkeypatch.setenv(X86_FALLBACK_ENV_VAR, enabled_value)

    # act / assert
    assert x86_fallback_enabled()


def test_fallback_is_enabled_by_default(monkeypatch):
    # arrange
    monkeypatch.delenv(X86_FALLBACK_ENV_VAR, raising=False)

    # act / assert
    assert x86_fallback_enabled()


def test_graviton_allow_key_opts_a_single_cluster_out():
    # arrange
    cfg = {
        GRAVITON_ALLOW_KEY: True,
        "master_node_type_id": "r6g.xlarge",
        "core_nodes": {"instance_types": ["r6g.xlarge", "r7g.xlarge"]},
    }

    # act
    apply_x86_fallback(cfg)

    # assert
    assert cfg["master_node_type_id"] == "r6g.xlarge"
    assert cfg["core_nodes"]["instance_types"] == ["r6g.xlarge", "r7g.xlarge"]
    assert GRAVITON_ALLOW_KEY not in cfg


def test_graviton_allow_key_set_to_false_still_remaps():
    # arrange
    cfg = {GRAVITON_ALLOW_KEY: False, "master_node_type_id": "r6g.xlarge"}

    # act
    apply_x86_fallback(cfg)

    # assert
    assert cfg["master_node_type_id"] == "r6a.xlarge"
    assert GRAVITON_ALLOW_KEY not in cfg
