from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Sequence
from urllib.parse import urlparse

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


# Required YAML keys (see ``config/*.yml``).
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
        "dump_logs_base_uri",
        "staging_uri",
        "visible_to_all_users",
        "master_instance_type",
        "core_instance_type",
        "core_instance_count",
        "idle_timeout_sec",
        "use_spot",
        "applications",
        "configurations",
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
    """Remote bootstrap script URI after staging: ``s3://`` only (no http(s))."""
    u = uri.strip()
    if not u:
        raise ValueError("bootstrap_script_uri must be non-empty")
    if not u.lower().startswith("s3://"):
        raise ValueError("bootstrap_script_uri must start with s3://")
    return u


def validate_staging_uri(uri: str) -> str:
    """S3 prefix for staging local uploads: ``s3://bucket/non-empty/prefix/`` (not bucket root)."""
    u = uri.strip()
    if not u.lower().startswith("s3://"):
        raise ValueError("staging_uri must be an s3:// URI")
    rest = u[5:]
    if "/" not in rest:
        raise ValueError(
            "staging_uri must be s3://bucket/prefix/ (bucket-only URIs are not allowed)"
        )
    bucket, prefix = rest.split("/", 1)
    if not bucket:
        raise ValueError("staging_uri must include a bucket name")
    if not prefix or not prefix.strip("/"):
        raise ValueError(
            "staging_uri must include a non-empty key prefix after the bucket "
            "(avoid staging at bucket root)"
        )
    return u if u.endswith("/") else u + "/"


def _resolve_bare_filesystem_path(raw: str, *, field: str) -> Path:
    """Bare path: absolute or relative to ``Path.cwd()`` only; must exist as a file."""
    local = Path(raw.strip()).expanduser()
    if not local.is_absolute():
        local = (Path.cwd() / local).resolve()
    else:
        local = local.resolve()
    if not local.is_file():
        raise ValueError(
            f"{field} must be s3:// or an existing file path (got {raw!r})"
        )
    return local


def normalize_job_or_bootstrap_uri(raw: str, *, field: str) -> str:
    """Accept ``s3://`` or a bare filesystem path (relative → cwd); ``file:`` URLs are not accepted."""
    s = raw.strip()
    if not s:
        raise ValueError(f"{field} must be non-empty")
    low = s.lower()
    if low.startswith(("http://", "https://")):
        raise ValueError(
            f"{field} must be s3:// or a local path (http(s) URLs are not supported)"
        )
    if low.startswith("s3://"):
        return s

    parsed = urlparse(s)
    if parsed.scheme:
        if parsed.scheme.lower() == "file":
            raise ValueError(
                f"{field} must be s3:// or a bare filesystem path "
                f"(file: URLs are not supported; pass the path instead, got {raw!r})"
            )
        raise ValueError(
            f"{field} must be s3:// or a bare filesystem path "
            f"(unsupported scheme {parsed.scheme!r} in {raw!r})"
        )

    return _resolve_bare_filesystem_path(s, field=field).as_uri()


def cli_emr_script_uri(uri: str, *, field: str) -> str:
    """Bootstrap from CLI: ``s3://`` or bare path (relative → cwd)."""
    normalized = normalize_job_or_bootstrap_uri(uri, field=field)
    if normalized.lower().startswith("file://"):
        return normalized
    return validate_bootstrap_script_uri(normalized)


# EMR AutoTerminationPolicy IdleTimeout (seconds): idle-only TTL, not wall-clock.
_IDLE_TIMEOUT_SEC_MIN = 60
_IDLE_TIMEOUT_SEC_MAX = 604800  # 7 days (AWS max)


def validate_emr_applications(raw: Any) -> list[dict[str, str]]:
    """Build EMR ``Applications`` payload: list of ``{\"Name\": \"Spark\"}`` dicts."""
    if not isinstance(raw, list) or not raw:
        raise ValueError("applications must be a non-empty YAML list")
    out: list[dict[str, str]] = []
    for item in raw:
        if isinstance(item, str):
            name = item.strip()
            if not name:
                raise ValueError("applications entries must be non-empty strings")
            out.append({"Name": name})
        elif isinstance(item, dict) and item.get("Name") is not None:
            name = str(item["Name"]).strip()
            if not name:
                raise ValueError("applications Name must be non-empty")
            out.append({"Name": name})
        else:
            raise ValueError(
                "applications entries must be strings or mappings with a Name field"
            )
    return out


def validate_emr_configurations(raw: Any) -> list[dict[str, Any]]:
    """EMR ``Configurations`` blocks (Iceberg/Delta/Glue metastore, etc.). Empty list allowed."""
    if raw is None:
        return []
    if not isinstance(raw, list):
        raise ValueError("configurations must be a YAML list")
    for item in raw:
        if not isinstance(item, dict):
            raise ValueError("each configurations entry must be a YAML mapping")
        if "Classification" not in item:
            raise ValueError(
                "each configurations entry must include a Classification field"
            )
    return list(raw)


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
        elif key in ("visible_to_all_users", "use_spot"):
            out[key] = bool(val)
        elif key == "core_instance_count":
            out[key] = _validate_core_instance_count(int(val))
        elif key in ("master_instance_type", "core_instance_type"):
            out[key] = _validate_instance_type(key, str(val))
        elif key == "idle_timeout_sec":
            out[key] = validate_idle_timeout_sec(int(val))
        elif key in ("staging_uri", "dump_logs_base_uri"):
            out[key] = validate_staging_uri(str(val))
        elif key == "applications":
            out[key] = validate_emr_applications(val)
        elif key == "configurations":
            out[key] = validate_emr_configurations(val)
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
    bootstrap_script_args: Sequence[str] | None = None,
    use_spot: bool | None = None,
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
    if use_spot is not None:
        cfg["use_spot"] = bool(use_spot)
    if bootstrap_script_uri is not None:
        cfg["bootstrap_script_uri"] = cli_emr_script_uri(
            bootstrap_script_uri, field="bootstrap_script_uri"
        )
    if bootstrap_script_args:
        cfg["bootstrap_script_args"] = [
            str(a).strip() for a in bootstrap_script_args if str(a).strip()
        ]
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
    bootstrap_script_args: Sequence[str] | None = None,
    job_script_args: Sequence[str] | None = None,
    use_spot: bool | None = None,
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
        bootstrap_script_args=bootstrap_script_args,
        use_spot=use_spot,
    )
    if s3_uri is not None:
        cfg["s3_uri"] = normalize_job_or_bootstrap_uri(s3_uri, field="uri")
    if step_name is not None:
        sn = step_name.strip()
        if not sn:
            raise ValueError("step_name must be non-empty")
        cfg["step_name"] = sn
    if job_script_args:
        cfg["job_script_args"] = [
            str(a).strip() for a in job_script_args if str(a).strip()
        ]
    return cfg


def merge_step_submit_config(
    *,
    config_path: str | Path,
    s3_uri: str,
    step_name: str,
    region: str | None = None,
    job_script_args: Sequence[str] | None = None,
) -> dict[str, Any]:
    """Settings file plus fields needed to add a Spark step to an existing cluster."""
    cfg = load_settings_file(config_path)
    cfg["s3_uri"] = normalize_job_or_bootstrap_uri(s3_uri, field="uri")
    sn = step_name.strip()
    if not sn:
        raise ValueError("step_name must be non-empty")
    cfg["step_name"] = sn
    if region is not None:
        r = region.strip()
        if not r:
            raise ValueError("region must be non-empty when set")
        cfg["region"] = r
    if job_script_args:
        cfg["job_script_args"] = [
            str(a).strip() for a in job_script_args if str(a).strip()
        ]
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
