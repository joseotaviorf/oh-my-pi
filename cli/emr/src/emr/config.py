from __future__ import annotations

import os
from pathlib import Path
from typing import Any

import yaml

# Paths inside the container (Compose mounts ./config → /config).
SETTINGS_PATH_PROD = "/config/prod.yml"
SETTINGS_PATH_FORNO = "/config/forno.yaml"
DEFAULT_ENVIRONMENT = "prod"


def resolve_settings_path() -> str:
    """Resolve settings file from ``EMR_ENVIRONMENT`` (``prod`` or ``forno``).

    Empty or unset ``EMR_ENVIRONMENT`` defaults to ``prod`` → ``SETTINGS_PATH_PROD``.
    """
    raw = os.environ.get("EMR_ENVIRONMENT", "")
    env = raw.strip().lower()
    if not env:
        env = DEFAULT_ENVIRONMENT
    if env == "prod":
        return SETTINGS_PATH_PROD
    if env == "forno":
        return SETTINGS_PATH_FORNO
    raise ValueError(
        "EMR_ENVIRONMENT must be 'prod' or 'forno' "
        f"(empty defaults to prod); got {raw!r}"
    )


# Only these keys are read from the YAML settings file. Per-job fields (name, step_name, tags) come from the CLI.
SETTINGS_FILE_KEYS = frozenset[str](
    {
        "release_label",
        "subnet_id",
        "job_flow_role",
        "service_role",
        "poll_sec",
        "action_on_failure",
        "deploy_mode",
        "region",
        "log_uri",
        "visible_to_all_users",
        "master_instance_type",
        "core_instance_type",
        "core_instance_count",
        "idle_timeout_sec",
    }
)


def _validate_instance_type(key: str, value: str) -> str:
    s = value.strip()
    if not s:
        raise ValueError(f"{key} must be a non-empty string")
    return s


def _validate_core_instance_count(n: int) -> int:
    if n < 1:
        raise ValueError("core_instance_count must be >= 1")
    return n


def validate_bootstrap_script_uri(uri: str) -> str:
    """EMR ScriptBootstrapAction Path: s3, http, or https URI."""
    u = uri.strip()
    if not u:
        raise ValueError("bootstrap_script_uri must be non-empty")
    lower = u.lower()
    if not (
        lower.startswith("s3://")
        or lower.startswith("https://")
        or lower.startswith("http://")
    ):
        raise ValueError(
            "bootstrap_script_uri must start with s3://, http://, or https://"
        )
    return u


# EMR AutoTerminationPolicy IdleTimeout (seconds): idle-only TTL, not wall-clock.
_IDLE_TIMEOUT_SEC_MIN = 60
_IDLE_TIMEOUT_SEC_MAX = 604800  # 7 days (AWS max)


def validate_idle_timeout_sec(n: int) -> int:
    if n < _IDLE_TIMEOUT_SEC_MIN or n > _IDLE_TIMEOUT_SEC_MAX:
        raise ValueError(
            f"idle_timeout_sec must be between {_IDLE_TIMEOUT_SEC_MIN} and "
            f"{_IDLE_TIMEOUT_SEC_MAX} (EMR AutoTerminationPolicy IdleTimeout)"
        )
    return int(n)


def load_settings_file(path: str | Path) -> dict[str, Any]:
    """Load settings YAML: every key in SETTINGS_FILE_KEYS is required; unknown keys are rejected."""
    raw_text = Path(path).read_text(encoding="utf-8")
    data = yaml.safe_load(raw_text)
    if data is None or data == {}:
        raise ValueError("Settings file must be a non-empty YAML mapping")
    if not isinstance(data, dict):
        raise ValueError("Settings file root must be a mapping (YAML object)")

    unknown = set[Any](data.keys()) - SETTINGS_FILE_KEYS
    if unknown:
        raise ValueError(
            f"Unknown settings keys (remove or fix): {', '.join(sorted(unknown))}"
        )

    missing = SETTINGS_FILE_KEYS - set[Any](data.keys())
    if missing:
        raise ValueError(
            f"Missing required settings keys: {', '.join(sorted(missing))}"
        )

    out: dict[str, Any] = {}
    for key in SETTINGS_FILE_KEYS:
        val = data[key]
        if val is None:
            raise ValueError(f"Settings key {key!r} must not be null")
        if key == "poll_sec":
            out[key] = float(val)
        elif key == "visible_to_all_users":
            out[key] = bool(val)
        elif key == "core_instance_count":
            out[key] = _validate_core_instance_count(int(val))
        elif key in ("master_instance_type", "core_instance_type"):
            out[key] = _validate_instance_type(key, str(val))
        elif key == "idle_timeout_sec":
            out[key] = validate_idle_timeout_sec(int(val))
        else:
            out[key] = val
    return out


def merge_base_config(
    *,
    config_path: str | Path,
    name: str | None = None,
    tags: dict[str, str] | None = None,
    master_instance_type: str | None = None,
    core_instance_type: str | None = None,
    core_instance_count: int | None = None,
    bootstrap_script_uri: str | None = None,
) -> dict[str, Any]:
    """Load YAML settings plus shared CLI overrides (tags, instances, bootstrap)."""
    cfg = load_settings_file(config_path)
    if name is not None:
        nm = name.strip()
        if not nm:
            raise ValueError("name must be non-empty")
        cfg["name"] = nm
    if master_instance_type is not None:
        cfg["master_instance_type"] = _validate_instance_type(
            "master_instance_type", master_instance_type
        )
    if core_instance_type is not None:
        cfg["core_instance_type"] = _validate_instance_type(
            "core_instance_type", core_instance_type
        )
    if core_instance_count is not None:
        cfg["core_instance_count"] = _validate_core_instance_count(core_instance_count)
    if bootstrap_script_uri is not None:
        cfg["bootstrap_script_uri"] = validate_bootstrap_script_uri(
            bootstrap_script_uri
        )
    # EMR RunJobFlow Tags: list of {Key, Value}. Required for AmazonEMRServicePolicy_v2-scoped EC2 API calls.
    emr_tags: list[dict[str, str]] = []
    if tags is not None:
        normalized = normalize_tags(tags)
        if normalized:
            emr_tags.extend(normalized)
    emr_tags.append(
        {"Key": "for-use-with-amazon-emr-managed-policies", "Value": "true"}
    )
    cfg["tags"] = emr_tags
    return cfg


def merge_runtime_config(
    *,
    config_path: str | Path,
    s3_uri: str | None = None,
    step_name: str | None = None,
    name: str | None = None,
    tags: dict[str, str] | None = None,
    master_instance_type: str | None = None,
    core_instance_type: str | None = None,
    core_instance_count: int | None = None,
    bootstrap_script_uri: str | None = None,
) -> dict[str, Any]:
    """Load settings from YAML, then apply per-run CLI fields (do not appear in the YAML file)."""
    cfg = merge_base_config(
        config_path=config_path,
        name=name,
        tags=tags,
        master_instance_type=master_instance_type,
        core_instance_type=core_instance_type,
        core_instance_count=core_instance_count,
        bootstrap_script_uri=bootstrap_script_uri,
    )
    if s3_uri is not None:
        cfg["s3_uri"] = s3_uri
    if step_name is not None:
        sn = step_name.strip()
        if not sn:
            raise ValueError("step_name must be non-empty")
        cfg["step_name"] = sn
    return cfg


def merge_step_submit_config(
    *,
    config_path: str | Path,
    s3_uri: str,
    step_name: str,
    region: str | None = None,
) -> dict[str, Any]:
    """Settings file plus fields needed to add a Spark step to an existing cluster."""
    cfg = load_settings_file(config_path)
    cfg["s3_uri"] = s3_uri
    sn = step_name.strip()
    if not sn:
        raise ValueError("step_name must be non-empty")
    cfg["step_name"] = sn
    if region is not None:
        r = region.strip()
        if not r:
            raise ValueError("region must be non-empty when set")
        cfg["region"] = r
    return cfg


def normalize_tags(tags: Any) -> list[dict[str, str]] | None:
    """Accept list of {Key:, Value:} or mapping key -> value."""
    if tags is None:
        return None
    if isinstance(tags, dict):
        return [{"Key": str(k), "Value": str(v)} for k, v in tags.items()]
    if isinstance(tags, list):
        out = []
        for item in tags:
            if isinstance(item, dict) and "Key" in item and "Value" in item:
                out.append({"Key": str(item["Key"]), "Value": str(item["Value"])})
            else:
                raise ValueError("tags list entries must be {Key, Value} mappings")
        return out
    raise ValueError("tags must be a dict or a list of {Key, Value}")


def _require_py_s3_uri(s3_uri: str) -> None:
    key = s3_uri.split("?", 1)[0].rsplit("/", 1)[-1]
    if not key.lower().endswith(".py"):
        raise ValueError(
            "s3_uri must be a PySpark script ending in .py (JARs are not supported)"
        )


def validate_transient(cfg: dict[str, Any]) -> None:
    missing = [k for k in ("s3_uri", "name", "step_name") if not cfg.get(k)]
    missing.extend(
        k
        for k in ("release_label", "subnet_id", "job_flow_role", "service_role")
        if not cfg.get(k)
    )
    if missing:
        raise ValueError(
            f"Missing required fields for transient cluster: {', '.join(sorted(set(missing)))}"
        )
    _require_py_s3_uri(str(cfg["s3_uri"]))
    if cfg.get("bootstrap_script_uri"):
        validate_bootstrap_script_uri(str(cfg["bootstrap_script_uri"]))


def validate_persistent_cluster(cfg: dict[str, Any]) -> None:
    missing = [k for k in ("name",) if not cfg.get(k)]
    missing.extend(
        k
        for k in ("release_label", "subnet_id", "job_flow_role", "service_role")
        if not cfg.get(k)
    )
    if missing:
        raise ValueError(
            f"Missing required fields for persistent cluster: {', '.join(sorted(set(missing)))}"
        )
    if cfg.get("bootstrap_script_uri"):
        validate_bootstrap_script_uri(str(cfg["bootstrap_script_uri"]))
    validate_idle_timeout_sec(int(cfg["idle_timeout_sec"]))


def validate_step_submit(cfg: dict[str, Any]) -> None:
    missing = [k for k in ("s3_uri", "step_name") if not cfg.get(k)]
    missing.extend(k for k in ("action_on_failure", "deploy_mode") if not cfg.get(k))
    if missing:
        raise ValueError(
            f"Missing required fields for step submit: {', '.join(sorted(set(missing)))}"
        )
    _require_py_s3_uri(str(cfg["s3_uri"]))
