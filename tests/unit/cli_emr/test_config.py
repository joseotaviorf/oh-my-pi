"""Unit tests for ``emr.config`` (no AWS calls)."""

from __future__ import annotations

import textwrap
from pathlib import Path

import pytest

from emr.config import (
    SETTINGS_PATH_FORNO,
    SETTINGS_PATH_PROD,
    load_settings_file,
    normalize_tags,
    resolve_settings_path,
    validate_bootstrap_script_uri,
    validate_idle_timeout_sec,
    validate_persistent_cluster,
    validate_step_submit,
    validate_transient,
)


def test_resolve_settings_path_unset_uses_prod(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("EMR_ENVIRONMENT", raising=False)
    assert resolve_settings_path() == SETTINGS_PATH_PROD


def test_resolve_settings_path_empty_env_uses_prod(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("EMR_ENVIRONMENT", "")
    assert resolve_settings_path() == SETTINGS_PATH_PROD


def test_resolve_settings_path_whitespace_only_env_uses_prod(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("EMR_ENVIRONMENT", "   ")
    assert resolve_settings_path() == SETTINGS_PATH_PROD


def test_resolve_settings_path_forno(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("EMR_ENVIRONMENT", "forno")
    assert resolve_settings_path() == SETTINGS_PATH_FORNO


def test_resolve_settings_path_prod_explicit(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("EMR_ENVIRONMENT", "prod")
    assert resolve_settings_path() == SETTINGS_PATH_PROD


def test_resolve_settings_path_invalid_raises(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("EMR_ENVIRONMENT", "staging")
    with pytest.raises(ValueError, match="prod.*forno"):
        resolve_settings_path()


def test_validate_bootstrap_script_uri_accepts_s3() -> None:
    assert validate_bootstrap_script_uri("s3://b/k.sh").startswith("s3://")


def test_validate_bootstrap_script_uri_rejects_invalid() -> None:
    with pytest.raises(ValueError, match="must start with"):
        validate_bootstrap_script_uri("file:///tmp/x.sh")


def test_validate_idle_timeout_sec_bounds() -> None:
    with pytest.raises(ValueError):
        validate_idle_timeout_sec(30)
    with pytest.raises(ValueError):
        validate_idle_timeout_sec(9999999)
    assert validate_idle_timeout_sec(600) == 600


def test_load_settings_file_rejects_unknown_keys(tmp_path: Path) -> None:
    p = tmp_path / "s.yaml"
    p.write_text(
        textwrap.dedent(
            """
            region: us-east-1
            release_label: emr-7.5.0
            subnet_id: subnet-x
            job_flow_role: role
            service_role: arn:aws:iam::1:role/R
            poll_sec: 15.0
            action_on_failure: TERMINATE_CLUSTER
            deploy_mode: cluster
            log_uri: s3://b/l/
            visible_to_all_users: true
            master_instance_type: m5.xlarge
            core_instance_type: m5.xlarge
            core_instance_count: 2
            idle_timeout_sec: 600
            extra_bad: true
            """
        ).strip(),
        encoding="utf-8",
    )
    with pytest.raises(ValueError, match="Unknown settings keys"):
        load_settings_file(p)


def test_load_settings_file_ok(tmp_path: Path) -> None:
    p = tmp_path / "s.yaml"
    p.write_text(
        textwrap.dedent(
            """
            region: us-east-1
            release_label: emr-7.5.0
            subnet_id: subnet-x
            job_flow_role: role
            service_role: arn:aws:iam::1:role/R
            poll_sec: 15.0
            action_on_failure: TERMINATE_CLUSTER
            deploy_mode: cluster
            log_uri: s3://b/l/
            visible_to_all_users: true
            master_instance_type: m5.xlarge
            core_instance_type: m5.xlarge
            core_instance_count: 2
            idle_timeout_sec: 600
            """
        ).strip(),
        encoding="utf-8",
    )
    cfg = load_settings_file(p)
    assert cfg["region"] == "us-east-1"
    assert cfg["core_instance_count"] == 2
    assert cfg["visible_to_all_users"] is True


def test_normalize_tags_dict() -> None:
    out = normalize_tags({"a": "1", "b": "2"})
    assert out == [{"Key": "a", "Value": "1"}, {"Key": "b", "Value": "2"}]


def test_validate_transient_requires_py_suffix(tmp_path: Path) -> None:
    p = _write_minimal_settings(tmp_path / "emr-settings.yaml")
    from emr.config import merge_runtime_config

    cfg = merge_runtime_config(
        config_path=p,
        s3_uri="s3://b/job.jar",
        step_name="s",
        name="n",
    )
    with pytest.raises(ValueError, match="\\.py"):
        validate_transient(cfg)


def test_validate_transient_ok(tmp_path: Path) -> None:
    p = _write_minimal_settings(tmp_path / "emr-settings.yaml")
    from emr.config import merge_runtime_config

    cfg = merge_runtime_config(
        config_path=p,
        s3_uri="s3://b/job.py",
        step_name="step",
        name="flow",
    )
    validate_transient(cfg)


def test_validate_persistent_cluster_ok(tmp_path: Path) -> None:
    p = _write_minimal_settings(tmp_path / "emr-settings.yaml")
    from emr.config import merge_base_config

    cfg = merge_base_config(config_path=p, name="my-cluster")
    validate_persistent_cluster(cfg)


def test_validate_step_submit_ok(tmp_path: Path) -> None:
    p = _write_minimal_settings(tmp_path / "emr-settings.yaml")
    from emr.config import merge_step_submit_config

    cfg = merge_step_submit_config(
        config_path=p,
        s3_uri="s3://b/x.py",
        step_name="s",
        region="us-east-1",
    )
    validate_step_submit(cfg)


def _write_minimal_settings(path: Path) -> Path:
    path.write_text(
        textwrap.dedent(
            """
            region: us-east-1
            release_label: emr-7.5.0
            subnet_id: subnet-x
            job_flow_role: role
            service_role: arn:aws:iam::1:role/R
            poll_sec: 15.0
            action_on_failure: TERMINATE_CLUSTER
            deploy_mode: cluster
            log_uri: s3://b/l/
            visible_to_all_users: true
            master_instance_type: m5.xlarge
            core_instance_type: m5.xlarge
            core_instance_count: 2
            idle_timeout_sec: 600
            """
        ).strip(),
        encoding="utf-8",
    )
    return path
