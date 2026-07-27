"""Build Wonka DAGs at parse time from the quintoml S3 config registry (option A).

quintoml CI publishes one ``config.json`` per Wonka job (pure data:
``{job_name, job_module, job_config, build_info}``) plus a single
``manifest.json`` under ``<artifacts_bucket>/quintoml/registry/``. This service
fetches the manifest, validates each config against a Cerberus schema, and
builds the DAGs with bietlejuice's ``FactoryDispatcher`` — replicating
quintoflow's ``BietlejuiceDAGBuilder`` without importing quintoflow.

Entry point: ``register_wonka_dags_from_registry(globals())`` called from
``dags/quintoml/wonka_registry_factory.py``.

Environment:
  WONKA_REGISTRY_ENABLED  kill switch; ``0``/``false`` disables (default on).
  WONKA_REGISTRY_URI      manifest URI override (s3:// or local path). Default:
                          ConfigurationService ``artifacts_bucket`` +
                          ``quintoml/registry/manifest.json``.
  WONKA_REGISTRY_TTL      S3 cache TTL seconds for the manifest (default 300).
                          Per-job configs are also content-addressed by the
                          manifest ``sha256``: a disk-cache hit with matching
                          checksum skips S3 even after TTL expiry.
  WONKA_REGISTRY_CACHE    local cache directory (default /tmp/wonka_registry_cache).
  WONKA_REGISTRY_ROLE_ARN optional IAM role ARN to ``sts:AssumeRole`` before
                          S3 reads (mirrors prod's explicit assume-role pattern).
                          Unset = default boto3 credential chain (local / tests).

Failure semantics:
  - Manifest absent (S3 NoSuchKey / local file missing): registry not
    provisioned for this environment — info log, register nothing.
  - Manifest or config fetch error (network/auth): stale cache if available,
    else raise so the DAG file gets an import error and Airflow keeps the
    previously serialized DAGs instead of deleting them.
  - Malformed manifest (non-object, non-list jobs, wrong schema_version):
    raise a clear ValueError (import error, bag preserved).
  - Per-job config-quality failure (schema, checksum, build error, malformed
    entry): skip that job, log, continue. If the manifest lists jobs but
    zero could be registered, raise instead of silently emptying the bag.
  - Duplicate dag_id across jobs: keep the first, log an error.
  - Validation shadow DAG failure: log, keep the production DAG (mirrors the
    generated shim's behavior).
"""

from __future__ import annotations

import copy
import hashlib
import json
import logging
import os
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import urlparse

import boto3
from airflow.datasets import Dataset
from botocore.exceptions import ClientError
from cerberus import Validator

from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.validation.cluster_args import merge_validation_cluster_args
from bietlejuice.services.configuration_service import ConfigurationService

_LOG = logging.getLogger("wonka_registry_service")

MANIFEST_SCHEMA_VERSION = 1
REGISTRY_MANIFEST_SUFFIX = "quintoml/registry/manifest.json"
# Re-assume this many seconds before the STS session expires.
_ASSUME_ROLE_REFRESH_SKEW_SECONDS = 60
_ASSUME_ROLE_SESSION_NAME = "wonka-registry-dag-parse"
# Parallel S3 GETs for cold-cache registry configs (sha hits stay local).
_CONFIG_FETCH_WORKERS = 16

# Cached (client, expiry_epoch) when WONKA_REGISTRY_ROLE_ARN is set.
_s3_client_cache: Optional[tuple] = None


class RegistryUnavailableError(RuntimeError):
    """Manifest could not be fetched and no cached copy exists."""


class _RegistryObjectMissing(Exception):
    """The requested S3 object / local file does not exist."""


# Cerberus schema for registry config entries (the trust boundary between
# quintoml-published data and this Airflow deployment).
CONFIG_SCHEMA: Dict[str, Any] = {
    "job_name": {"type": "string", "required": True, "minlength": 1},
    "job_module": {"type": "string", "required": True},
    "job_config": {
        "type": "dict",
        "required": True,
        "schema": {
            "dag": {"type": "dict", "required": True},
            "workflow": {
                "type": "dict",
                "required": True,
                "schema": {
                    "type": {
                        "type": "string",
                        "required": True,
                        "allowed": ["wonka"],
                    },
                    "layer": {"type": "string", "required": True},
                },
                "allow_unknown": True,
            },
            "cluster": {"type": "dict", "required": True},
            "validation": {"type": "dict", "required": False},
        },
        "allow_unknown": True,
    },
    "build_info": {
        "type": "dict",
        "required": True,
        "schema": {
            "artifact_path": {"type": "string", "required": True},
            "commit": {"type": "string", "nullable": True, "required": False},
            "branch": {"type": "string", "nullable": True, "required": False},
            "ci_pipeline_url": {
                "type": "string",
                "nullable": True,
                "required": False,
            },
            "ci_pipeline_created": {
                "type": "string",
                "nullable": True,
                "required": False,
            },
            "context": {"type": "string", "nullable": True, "required": False},
        },
        "allow_unknown": True,
    },
}


def _enabled() -> bool:
    return os.environ.get("WONKA_REGISTRY_ENABLED", "1").strip().lower() not in (
        "0",
        "false",
    )


def _cache_dir() -> Path:
    return Path(os.environ.get("WONKA_REGISTRY_CACHE", "/tmp/wonka_registry_cache"))


def _ttl_seconds() -> int:
    raw = os.environ.get("WONKA_REGISTRY_TTL", "300")
    try:
        return int(raw)
    except ValueError:
        _LOG.warning("invalid WONKA_REGISTRY_TTL %r; using default 300", raw)
        return 300


def _role_arn() -> Optional[str]:
    raw = os.environ.get("WONKA_REGISTRY_ROLE_ARN", "").strip()
    return raw or None


def _reset_s3_client_cache() -> None:
    """Drop the cached assume-role S3 client (tests / forced re-assume)."""
    global _s3_client_cache
    _s3_client_cache = None


def _s3_client():
    """Return an S3 client, optionally via ``sts:AssumeRole``.

    When ``WONKA_REGISTRY_ROLE_ARN`` is unset, uses the default boto3 chain
    (local runs, unit tests, seeding tool). When set, assumes that role from
    the pod's Astro-managed identity — the same pattern prod uses for
    customer IAM roles — and caches the client until near STS expiry.
    """
    role_arn = _role_arn()
    if not role_arn:
        return boto3.client("s3")

    global _s3_client_cache
    now = time.time()
    if _s3_client_cache is not None:
        client, expiry = _s3_client_cache
        if now < expiry - _ASSUME_ROLE_REFRESH_SKEW_SECONDS:
            return client

    sts = boto3.client("sts")
    assumed = sts.assume_role(
        RoleArn=role_arn,
        RoleSessionName=_ASSUME_ROLE_SESSION_NAME,
    )
    creds = assumed["Credentials"]
    client = boto3.client(
        "s3",
        aws_access_key_id=creds["AccessKeyId"],
        aws_secret_access_key=creds["SecretAccessKey"],
        aws_session_token=creds["SessionToken"],
    )
    expiry = creds["Expiration"].timestamp()
    _s3_client_cache = (client, expiry)
    return client


def registry_manifest_uri() -> str:
    """Manifest URI: env override, else conf-resolved artifacts bucket."""
    override = os.environ.get("WONKA_REGISTRY_URI")
    if override:
        return override
    artifacts_bucket = ConfigurationService().get_config("artifacts_bucket")
    return f"{artifacts_bucket.rstrip('/')}/{REGISTRY_MANIFEST_SUFFIX}"


def _fetch_bytes(uri: str, *, force: bool = False) -> bytes:
    """Read bytes from an s3:// URI (TTL-cached) or a local path.

    Raises ``_RegistryObjectMissing`` when the object/file does not exist and
    ``RegistryUnavailableError`` on other S3 failures with no cached copy.
    """
    if uri.startswith("s3://"):
        return _fetch_s3_bytes_cached(uri, force=force)
    path = Path(uri)
    if not path.exists():
        raise _RegistryObjectMissing(uri)
    return path.read_bytes()


def _cache_paths(uri: str) -> tuple:
    """Cache file + meta file for an S3 URI.

    The readable prefix is suffixed with a hash of the full URI so distinct
    keys can never collide after the ``/`` -> ``__`` flattening.
    """
    key = urlparse(uri).path.lstrip("/")
    digest = hashlib.sha256(uri.encode()).hexdigest()[:12]
    cache_file = _cache_dir() / f"{key.replace('/', '__')}-{digest}"
    return cache_file, Path(str(cache_file) + ".meta")


def _fetch_s3_bytes_cached(uri: str, *, force: bool = False) -> bytes:
    parsed = urlparse(uri)
    bucket = parsed.netloc
    key = parsed.path.lstrip("/")
    _cache_dir().mkdir(parents=True, exist_ok=True)
    cache_file, meta_file = _cache_paths(uri)

    now = time.time()
    if not force and cache_file.exists() and meta_file.exists():
        try:
            fetched_at = float(meta_file.read_text().strip())
            if now - fetched_at < _ttl_seconds():
                return cache_file.read_bytes()
        except (ValueError, OSError):
            pass

    try:
        client = _s3_client()
        obj = client.get_object(Bucket=bucket, Key=key)
        body = obj["Body"].read()
    except ClientError as e:
        code = e.response.get("Error", {}).get("Code", "")
        if code in ("NoSuchKey", "404", "NotFound"):
            raise _RegistryObjectMissing(uri) from e
        _LOG.warning("S3 fetch failed for %s (%s); trying stale cache", uri, e)
        if cache_file.exists():
            return cache_file.read_bytes()
        raise RegistryUnavailableError(f"cannot fetch {uri}: {e}") from e
    except Exception as e:  # botocore network errors, credential errors, ...
        _LOG.warning("S3 fetch failed for %s (%s); trying stale cache", uri, e)
        if cache_file.exists():
            return cache_file.read_bytes()
        raise RegistryUnavailableError(f"cannot fetch {uri}: {e}") from e

    cache_file.write_bytes(body)
    meta_file.write_text(str(now))
    return body


def validate_config(entry: Dict[str, Any]) -> List[str]:
    """Return a list of validation errors (empty if valid)."""
    validator = Validator(CONFIG_SCHEMA, allow_unknown=True)
    if validator.validate(entry):
        deps = entry.get("job_config", {}).get("dag", {}).get("dataset_dependencies")
        if deps is not None and not isinstance(deps, list):
            return ["dag.dataset_dependencies must be a list when present"]
        if isinstance(deps, list):
            # Airflow dataset URIs are arbitrary non-empty strings (live prod
            # includes plain table names like datalake_x.some_table).
            for d in deps:
                if not isinstance(d, str) or not d.strip():
                    return [f"invalid dataset dependency URI: {d!r}"]
        return []
    return [f"{k}: {v}" for k, v in (validator.errors or {}).items()]


def prepare_dag_args(
    job_name: str, job_config: Dict[str, Any], build_info: Dict[str, Any]
) -> Dict[str, Any]:
    """Mirror quintoflow ``BietlejuiceDAGBuilder._prepare_dag_args``."""
    dag_args = copy.deepcopy(job_config.get("dag", {}))
    dag_args.update(build_info)
    # The manifest job_name is the canonical DAG identity: a stray "name" key
    # inside build_info must not be able to override it (quintoflow relies on
    # its generated shims for this; the registry enforces it explicitly).
    dag_args["name"] = job_name
    return dag_args


def prepare_dataset_dependencies(
    dataset_dependencies: Optional[List[str]],
) -> Optional[List[Dataset]]:
    if not dataset_dependencies:
        return None
    return [Dataset(dep) for dep in dataset_dependencies]


def _build_factory(
    dag_args: Dict[str, Any],
    workflow_args: Dict[str, Any],
    cluster_args: Dict[str, Any],
    validation_config: Optional[Dict[str, Any]],
    *,
    is_validation: bool,
):
    """Mirror quintoflow ``BietlejuiceDAGBuilder._build_factory``."""
    # Lazy import: the dispatcher pulls the full DAG-builder tree (including
    # `dags/` package paths only available inside the Airflow deployment).
    from bietlejuice.base.airflow.dag_builders.main_builder.factories.factory_dispatcher import (  # noqa: E501
        FactoryDispatcher,
    )

    layer = workflow_args.get("layer")
    if not layer:
        raise ValueError("workflow.layer is required")

    dataset_dependencies = prepare_dataset_dependencies(
        dag_args.get("dataset_dependencies", [])
    )
    validation_kwargs: Dict[str, Any] = {}
    if is_validation:
        validation_cluster = (validation_config or {}).get("cluster")
        if not validation_cluster:
            raise ValueError("validation.cluster is required for validation DAG")
        cluster_args = merge_validation_cluster_args(cluster_args, validation_cluster)
        dataset_dependencies = None
        validation_kwargs = {
            "is_validation": True,
            "validation_config": validation_config,
        }

    return FactoryDispatcher(layer=LayerEnum(layer)).get_factory(
        dag_args=copy.deepcopy(dag_args),
        workflow_args=copy.deepcopy(workflow_args),
        cluster_args=cluster_args,
        dataset_dependencies=dataset_dependencies,
        **validation_kwargs,
    )


def build_dags_from_config(entry: Dict[str, Any]) -> List[Any]:
    """Validate and build the production DAG (+ validation shadow DAG if configured).

    A validation-DAG failure is logged and the production DAG kept, mirroring
    the generated shim's behavior.
    """
    errors = validate_config(entry)
    if errors:
        raise ValueError(f"invalid registry config: {errors}")

    job_name = entry["job_name"]
    job_config = entry["job_config"]
    build_info = entry["build_info"]
    dag_args = prepare_dag_args(job_name, job_config, build_info)
    workflow_args = job_config.get("workflow", {})
    cluster_args = job_config.get("cluster", {})
    validation_config = job_config.get("validation")

    factory = _build_factory(
        dag_args, workflow_args, cluster_args, validation_config, is_validation=False
    )
    dags = [factory.get_workflow().build_dag()]

    if (validation_config or {}).get("cluster"):
        try:
            validation_factory = _build_factory(
                dag_args,
                workflow_args,
                cluster_args,
                validation_config,
                is_validation=True,
            )
            dags.append(validation_factory.get_workflow().build_dag())
        except Exception:
            _LOG.exception(
                "Failed to build validation DAG for %s; production DAG remains "
                "registered.",
                job_name,
            )
    return dags


def load_manifest() -> Optional[Dict[str, Any]]:
    """Fetch and parse the registry manifest.

    Returns ``None`` when the registry is not provisioned (object missing).
    Raises ``RegistryUnavailableError`` on fetch failure with no cached copy.
    """
    uri = registry_manifest_uri()
    try:
        raw = _fetch_bytes(uri)
    except _RegistryObjectMissing:
        _LOG.info("Wonka registry not provisioned at %s; nothing to register", uri)
        return None
    manifest = json.loads(raw)
    # Contract violations raise clear ValueErrors: the resulting import error
    # preserves previously serialized DAGs instead of emptying the bag.
    if not isinstance(manifest, dict):
        raise ValueError(
            f"Wonka registry manifest at {uri} must be a JSON object, "
            f"got {type(manifest).__name__}"
        )
    schema_version = manifest.get("schema_version")
    if schema_version != MANIFEST_SCHEMA_VERSION:
        raise ValueError(
            f"unsupported Wonka registry schema_version {schema_version!r} "
            f"(expected {MANIFEST_SCHEMA_VERSION}) at {uri}"
        )
    jobs = manifest.get("jobs") or []
    if not isinstance(jobs, list):
        raise ValueError(
            f"Wonka registry manifest at {uri} has a non-list 'jobs' field"
        )
    manifest["jobs"] = jobs
    return manifest


def _job_config_uri(job_entry: Dict[str, Any]) -> str:
    """Resolve the config URI for a manifest job entry."""
    if "config_path" in job_entry:
        return job_entry["config_path"]
    manifest_uri = registry_manifest_uri()
    parsed = urlparse(manifest_uri)
    if parsed.scheme != "s3":
        raise ValueError("local manifests must use config_path per job entry")
    return f"s3://{parsed.netloc}/{job_entry['config_key']}"


def _read_sha_validated_cache(uri: str, expected_sha: str) -> Optional[bytes]:
    """Return cached S3 object bytes when they match ``expected_sha`` (TTL ignored).

    Manifest entries are content-addressed by sha256, so a hash match is an
    exact hit even after ``WONKA_REGISTRY_TTL`` expires. Local (non-s3) URIs
    skip this path and are read directly by ``_fetch_bytes``.
    """
    if not uri.startswith("s3://"):
        return None
    cache_file, _meta_file = _cache_paths(uri)
    if not cache_file.exists():
        return None
    try:
        cached = cache_file.read_bytes()
    except OSError:
        return None
    if hashlib.sha256(cached).hexdigest() == expected_sha:
        return cached
    return None


def _fetch_config_bytes(job_entry: Dict[str, Any]) -> bytes:
    """Fetch a job's config.json bytes, verifying its manifest sha256.

    Prefer a sha256-validated disk cache hit (no S3 GET, no TTL check). On
    checksum mismatch the object is re-fetched once bypassing the TTL cache
    (covers a fresh manifest paired with a stale cached config).
    """
    uri = _job_config_uri(job_entry)
    expected = job_entry.get("sha256")
    if not expected:
        raise ValueError(f"manifest entry for {uri} is missing sha256")

    cached = _read_sha_validated_cache(uri, expected)
    if cached is not None:
        return cached

    raw = _fetch_bytes(uri)
    if hashlib.sha256(raw).hexdigest() == expected:
        return raw
    raw = _fetch_bytes(uri, force=True)
    actual = hashlib.sha256(raw).hexdigest()
    if actual != expected:
        raise ValueError(
            f"checksum mismatch for {uri}: manifest={expected} fetched={actual}"
        )
    return raw


def _fetch_all_config_bytes(
    jobs: List[Any],
) -> List[Tuple[Any, Any]]:
    """Fetch every job config, parallelizing S3 misses.

    Returns a list of ``(job_entry, result)`` in manifest order. ``result`` is
    either ``bytes`` or an exception instance raised while fetching that job.
    Malformed (non-dict) entries are returned as ``(entry, None)``.
    """
    # Build the assume-role / default S3 client once on the calling thread so
    # workers share the module-level client cache without racing STS.
    if any(
        isinstance(je, dict)
        and (str(je.get("config_path", "")).startswith("s3://") or "config_key" in je)
        for je in jobs
    ):
        try:
            _s3_client()
        except Exception:  # noqa: BLE001 — individual fetches re-raise
            pass

    results: List[Tuple[Any, Any]] = [(None, None)] * len(jobs)

    def _one(index: int, job_entry: Any) -> Tuple[int, Any, Any]:
        if not isinstance(job_entry, dict):
            return index, job_entry, None
        try:
            return index, job_entry, _fetch_config_bytes(job_entry)
        except Exception as exc:  # noqa: BLE001 — re-raised by caller
            return index, job_entry, exc

    workers = min(_CONFIG_FETCH_WORKERS, max(1, len(jobs)))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = [pool.submit(_one, i, je) for i, je in enumerate(jobs)]
        for fut in as_completed(futures):
            index, job_entry, result = fut.result()
            results[index] = (job_entry, result)
    return results


def register_wonka_dags_from_registry(globals_dict: dict) -> int:
    """Fetch manifest, build DAGs, register into ``globals_dict``. Returns count."""
    if not _enabled():
        _LOG.info("Wonka registry disabled via WONKA_REGISTRY_ENABLED; skipping")
        return 0

    manifest = load_manifest()
    if manifest is None:
        return 0

    jobs = manifest["jobs"]
    count = 0
    for job_entry, fetch_result in _fetch_all_config_bytes(jobs):
        if not isinstance(job_entry, dict):
            _LOG.error("skipping malformed Wonka manifest entry: %r", job_entry)
            continue
        job_key = job_entry.get("job_key", "?")
        try:
            if isinstance(fetch_result, BaseException):
                raise fetch_result
            raw = fetch_result
            entry = json.loads(raw)
            for dag in build_dags_from_config(entry):
                if dag.dag_id in globals_dict:
                    _LOG.error(
                        "duplicate Wonka dag_id %s from job %s; keeping the "
                        "first definition",
                        dag.dag_id,
                        job_key,
                    )
                    continue
                globals_dict[dag.dag_id] = dag
                count += 1
        except RegistryUnavailableError:
            # Infrastructure failure fetching a config (no cached copy):
            # fail the import loudly so Airflow keeps the previously
            # serialized DAGs instead of silently shrinking the bag.
            raise
        except Exception:
            _LOG.exception("skipping Wonka job %s", job_key)
    if jobs and count == 0:
        raise RegistryUnavailableError(
            f"manifest lists {len(jobs)} Wonka jobs but none could be "
            "registered; failing the import to preserve previously "
            "serialized DAGs"
        )
    _LOG.info("registered %d Wonka DAGs from registry", count)
    return count
