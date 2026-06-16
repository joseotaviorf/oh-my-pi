"""Unit tests for ``emr.config`` (no AWS calls)."""

from __future__ import annotations

import textwrap
from pathlib import Path

import pytest

from emr.config import (
    cli_emr_script_uri,
    load_settings_file,
    normalize_job_or_bootstrap_uri,
    normalize_tags,
    resolve_settings_path,
    validate_bootstrap_script_uri,
    validate_idle_timeout_sec,
    validate_persistent_cluster,
    validate_step_submit,
    validate_transient,
)
from emr.paths import package_root


def _expected_default_path(env: str) -> str:
    name = "forno.yaml" if env == "forno" else "prod.yml"
    return str((package_root() / "config" / name).resolve())


def test_resolve_settings_path_unset_uses_prod(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("EMR_ENVIRONMENT", raising=False)
    monkeypatch.delenv("EMR_SETTINGS_FILE", raising=False)
    monkeypatch.delenv("EMR_CONFIG_DIR", raising=False)
    assert resolve_settings_path() == _expected_default_path("prod")


def test_resolve_settings_path_empty_env_uses_prod(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("EMR_ENVIRONMENT", "")
    monkeypatch.delenv("EMR_SETTINGS_FILE", raising=False)
    monkeypatch.delenv("EMR_CONFIG_DIR", raising=False)
    assert resolve_settings_path() == _expected_default_path("prod")


def test_resolve_settings_path_whitespace_only_env_uses_prod(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("EMR_ENVIRONMENT", "   ")
    monkeypatch.delenv("EMR_SETTINGS_FILE", raising=False)
    monkeypatch.delenv("EMR_CONFIG_DIR", raising=False)
    assert resolve_settings_path() == _expected_default_path("prod")


def test_resolve_settings_path_forno(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("EMR_ENVIRONMENT", "forno")
    monkeypatch.delenv("EMR_SETTINGS_FILE", raising=False)
    monkeypatch.delenv("EMR_CONFIG_DIR", raising=False)
    assert resolve_settings_path() == _expected_default_path("forno")


def test_resolve_settings_path_prod_explicit(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("EMR_ENVIRONMENT", "prod")
    monkeypatch.delenv("EMR_SETTINGS_FILE", raising=False)
    monkeypatch.delenv("EMR_CONFIG_DIR", raising=False)
    assert resolve_settings_path() == _expected_default_path("prod")


def test_resolve_settings_path_invalid_raises(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("EMR_ENVIRONMENT", "staging")
    monkeypatch.delenv("EMR_SETTINGS_FILE", raising=False)
    monkeypatch.delenv("EMR_CONFIG_DIR", raising=False)
    with pytest.raises(ValueError, match="prod.*forno"):
        resolve_settings_path()


def test_resolve_settings_path_emr_settings_file_overrides_env(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    p = tmp_path / "custom.yml"
    p.write_text("x: 1\n", encoding="utf-8")
    monkeypatch.setenv("EMR_SETTINGS_FILE", str(p))
    monkeypatch.setenv("EMR_ENVIRONMENT", "invalid-would-fail-if-used")
    assert resolve_settings_path() == str(p.resolve())


def test_resolve_settings_path_emr_settings_file_missing_raises(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    missing = tmp_path / "nope.yml"
    monkeypatch.setenv("EMR_SETTINGS_FILE", str(missing))
    with pytest.raises(ValueError, match="EMR_SETTINGS_FILE"):
        resolve_settings_path()


def test_resolve_settings_path_emr_config_dir(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    d = tmp_path / "cfg"
    d.mkdir()
    f = d / "forno.yaml"
    f.write_text("x: 1\n", encoding="utf-8")
    monkeypatch.setenv("EMR_CONFIG_DIR", str(d))
    monkeypatch.setenv("EMR_ENVIRONMENT", "forno")
    monkeypatch.delenv("EMR_SETTINGS_FILE", raising=False)
    assert resolve_settings_path() == str(f.resolve())


def test_package_root_resolves_checkout_config() -> None:
    """Default checkout layout: ``packages/emr-cli/config/*.yml`` exists."""
    from emr.paths import package_root

    root = package_root()
    assert (root / "config" / "prod.yml").is_file()
    assert (root / "config" / "forno.yaml").is_file()


def test_resolve_settings_path_default_missing_raises(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    empty_root = tmp_path / "emr-cli"
    (empty_root / "config").mkdir(parents=True)
    monkeypatch.setattr("emr.config.package_root", lambda: empty_root)
    monkeypatch.delenv("EMR_SETTINGS_FILE", raising=False)
    monkeypatch.delenv("EMR_CONFIG_DIR", raising=False)
    monkeypatch.delenv("EMR_ENVIRONMENT", raising=False)
    with pytest.raises(ValueError, match="Default settings file missing"):
        resolve_settings_path()


def test_resolve_settings_path_emr_config_dir_missing_file_raises(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    d = tmp_path / "cfg"
    d.mkdir()
    monkeypatch.setenv("EMR_CONFIG_DIR", str(d))
    monkeypatch.setenv("EMR_ENVIRONMENT", "prod")
    monkeypatch.delenv("EMR_SETTINGS_FILE", raising=False)
    with pytest.raises(ValueError, match="EMR_CONFIG_DIR"):
        resolve_settings_path()


def test_validate_bootstrap_script_uri_accepts_s3() -> None:
    assert validate_bootstrap_script_uri("s3://b/k.sh").startswith("s3://")


def test_validate_bootstrap_script_uri_rejects_invalid() -> None:
    with pytest.raises(ValueError, match="s3://"):
        validate_bootstrap_script_uri("file:///tmp/x.sh")


def test_normalize_job_or_bootstrap_uri_rejects_http() -> None:
    with pytest.raises(ValueError, match="http"):
        normalize_job_or_bootstrap_uri("https://example.com/x.py", field="uri")


def test_normalize_job_or_bootstrap_uri_bare_absolute_path(tmp_path: Path) -> None:
    f = tmp_path / "job.py"
    f.write_text("x", encoding="utf-8")
    out = normalize_job_or_bootstrap_uri(str(f), field="uri")
    assert out == f.resolve().as_uri()


def test_normalize_job_or_bootstrap_uri_bare_relative_resolves_from_cwd(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    nested = tmp_path / "nested" / "job.py"
    nested.parent.mkdir(parents=True)
    nested.write_text("x", encoding="utf-8")
    monkeypatch.chdir(tmp_path)

    out = normalize_job_or_bootstrap_uri("nested/job.py", field="uri")
    assert out == nested.resolve().as_uri()


def test_normalize_job_or_bootstrap_uri_rejects_file_scheme_uri(tmp_path: Path) -> None:
    f = tmp_path / "job.py"
    f.write_text("x", encoding="utf-8")
    uri = f.resolve().as_uri()
    with pytest.raises(ValueError, match="file: URLs are not supported"):
        normalize_job_or_bootstrap_uri(uri, field="uri")


def test_normalize_job_or_bootstrap_uri_rejects_non_s3_scheme() -> None:
    with pytest.raises(ValueError, match="unsupported scheme"):
        normalize_job_or_bootstrap_uri("ftp://x/y.py", field="uri")


def test_normalize_job_or_bootstrap_uri_remote_unchanged() -> None:
    s = "s3://b/k.py"
    assert normalize_job_or_bootstrap_uri(s, field="uri") == s


def test_cli_emr_script_uri_local_bare_path(tmp_path: Path) -> None:
    sh = tmp_path / "b.sh"
    sh.write_text("#!", encoding="utf-8")
    out = cli_emr_script_uri(str(sh), field="bootstrap_script_uri")
    assert out == sh.resolve().as_uri()


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
            dump_logs_base_uri: s3://b/emr/logs/cli/
            staging_uri: s3://b/emr/staging/cli/
            visible_to_all_users: true
            master_instance_type: m5.xlarge
            core_instance_type: m5.xlarge
            core_instance_count: 2
            idle_timeout_sec: 600
            use_spot: true
            applications:
              - Spark
            configurations: []
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
            dump_logs_base_uri: s3://b/emr/logs/cli/
            staging_uri: s3://b/emr/staging/cli/
            visible_to_all_users: true
            master_instance_type: m5.xlarge
            core_instance_type: m5.xlarge
            core_instance_count: 2
            idle_timeout_sec: 600
            use_spot: false
            applications:
              - Hadoop
              - Spark
            configurations: []
            """
        ).strip(),
        encoding="utf-8",
    )
    cfg = load_settings_file(p)
    assert cfg["region"] == "us-east-1"
    assert cfg["core_instance_count"] == 2
    assert cfg["visible_to_all_users"] is True
    assert cfg["use_spot"] is False
    assert cfg["staging_uri"] == "s3://b/emr/staging/cli/"
    assert cfg["dump_logs_base_uri"] == "s3://b/emr/logs/cli/"
    assert cfg["applications"] == [{"Name": "Hadoop"}, {"Name": "Spark"}]
    assert cfg["configurations"] == []


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


def test_merge_runtime_config_bootstrap_and_job_args(tmp_path: Path) -> None:
    p = _write_minimal_settings(tmp_path / "emr-settings.yaml")
    from emr.config import merge_runtime_config

    cfg = merge_runtime_config(
        config_path=p,
        s3_uri="s3://b/job.py",
        step_name="step",
        name="flow",
        bootstrap_script_args=("s3://artifacts.example",),
        job_script_args=("--target-table", "sandbox.t"),
    )
    assert cfg["bootstrap_script_args"] == ["s3://artifacts.example"]
    assert cfg["job_script_args"] == ["--target-table", "sandbox.t"]


def test_merge_step_submit_config_job_args(tmp_path: Path) -> None:
    p = _write_minimal_settings(tmp_path / "emr-settings.yaml")
    from emr.config import merge_step_submit_config

    cfg = merge_step_submit_config(
        config_path=p,
        s3_uri="s3://b/job.py",
        step_name="step",
        region="us-east-1",
        job_script_args=["--foo", "bar"],
    )
    assert cfg["job_script_args"] == ["--foo", "bar"]


def test_merge_runtime_config_overrides_use_spot(tmp_path: Path) -> None:
    p = _write_minimal_settings(tmp_path / "emr-settings.yaml")
    from emr.config import merge_runtime_config

    base = merge_runtime_config(
        config_path=p,
        s3_uri="s3://b/x.py",
        step_name="step",
        name="flow",
    )
    assert base["use_spot"] is True

    off = merge_runtime_config(
        config_path=p,
        s3_uri="s3://b/x.py",
        step_name="step",
        name="flow",
        use_spot=False,
    )
    assert off["use_spot"] is False


def test_validate_core_instance_count_allows_zero() -> None:
    from emr.config import _validate_core_instance_count

    assert _validate_core_instance_count(0) == 0


def test_merge_runtime_config_overrides_deploy_mode(tmp_path: Path) -> None:
    p = _write_minimal_settings(tmp_path / "emr-settings.yaml")
    from emr.config import merge_runtime_config

    cfg = merge_runtime_config(
        config_path=p,
        s3_uri="s3://b/x.py",
        step_name="step",
        name="flow",
        deploy_mode="cluster",
    )
    assert cfg["deploy_mode"] == "cluster"


def test_merge_step_submit_config_overrides_deploy_mode(tmp_path: Path) -> None:
    p = _write_minimal_settings(tmp_path / "emr-settings.yaml")
    from emr.config import merge_step_submit_config

    cfg = merge_step_submit_config(
        config_path=p,
        s3_uri="s3://b/x.py",
        step_name="step",
        deploy_mode="cluster",
    )
    assert cfg["deploy_mode"] == "cluster"


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
            dump_logs_base_uri: s3://b/emr/logs/cli/
            staging_uri: s3://b/emr/staging/cli/
            visible_to_all_users: true
            master_instance_type: m5.xlarge
            core_instance_type: m5.xlarge
            core_instance_count: 2
            idle_timeout_sec: 600
            use_spot: true
            applications:
              - Spark
            configurations: []
            """
        ).strip(),
        encoding="utf-8",
    )
    return path
