"""
Declaration loader for API Ingestion workflow.

Loads DAG declaration YAML for a given dag_name. Tries in order:
1. Local filesystem (Composer, local dev)
2. Installed package (Databricks - *_api_declaration.y*ml bundled via hatch build
   config in pyproject.toml)
3. S3/volume (legacy fallback)

Convention: api_ingestion DAGs are named with _api suffix (e.g. currency_api).
The declaration file is {dag_name}_declaration.yml. The hatch build config includes
only *_api_declaration.y*ml so only these DAGs are bundled in the wheel.
"""

import logging
import re
from os import path, scandir
from typing import Any, Callable, Dict, Iterator, Literal, Optional, Tuple, cast

import yaml

try:
    from importlib.resources import files as importlib_resource_files
except ImportError:
    importlib_resource_files = None

from bietlejuice.base.service.dag_packages_path_service import (
    DAGPackagesPathService,
)

LOGGER = logging.getLogger(__name__)

_VALID_DAG_NAME = re.compile(r"^[a-z0-9_]+$")

_LogKind = Literal["package", "s3"]


def _coerce_declaration_dict(raw: Any, source: str) -> Optional[Dict[str, Any]]:
    """
    Ensure loaded YAML is a mapping so callers can try the next resolution strategy.

    Args:
        raw: Parsed YAML value (typically from ``yaml.safe_load``).
        source: Human-readable origin label for logs (path, URI, or pseudo-label).

    Returns:
        The mapping cast to ``Dict[str, Any]``, or ``None`` if ``raw`` is null or
        not a dict (callers may attempt another loader).
    """
    if raw is None:
        LOGGER.warning(
            "Declaration at %s is empty or null; trying next source.", source
        )
        return None
    if not isinstance(raw, dict):
        LOGGER.warning(
            "Declaration at %s must be a YAML mapping, got %s; trying next source.",
            source,
            type(raw).__name__,
        )
        return None
    return cast(Dict[str, Any], raw)


def _validate_dag_name(dag_name: str) -> None:
    """
    Reject ``dag_name`` values that could cause path traversal.

    Args:
        dag_name: Candidate DAG identifier.

    Raises:
        ValueError: If empty or not matching ``[a-z0-9_]+``.
    """
    if not dag_name or not _VALID_DAG_NAME.match(dag_name):
        raise ValueError(
            f"Invalid dag_name '{dag_name}': must match [a-z0-9_]+ (snake_case). "
            "Path traversal characters are not allowed."
        )


def validate_api_ingestion_dag_name(dag_name: str) -> str:
    """
    Validate ``dag_name`` before any filesystem or network I/O (CWE-23).

    Call at entry points (e.g. Spark job CLI) so untrusted arguments are
    rejected before paths are built. Returns the same string when valid.

    Args:
        dag_name: Candidate DAG name from the orchestrator or CLI.

    Returns:
        The validated ``dag_name`` unchanged.

    Raises:
        ValueError: If ``dag_name`` is empty or contains disallowed characters.
    """
    _validate_dag_name(dag_name)
    return dag_name


def _iter_dag_domain_names() -> Iterator[str]:
    """
    Yield top-level domain folder names under ``DAG_PACKAGES_ROOT``.

    Skips non-directories and hidden/internal entries (e.g. ``__pycache__``).

    Yields:
        Domain folder name strings.
    """
    from dags import DAG_PACKAGES_ROOT

    for entry in scandir(DAG_PACKAGES_ROOT):
        if entry.is_dir() and not entry.name.startswith("_"):
            yield entry.name


def _try_read_declaration_from_package(
    files: Any,
    dag_name: str,
    domain: str,
    ext: str,
) -> Optional[Tuple[str, str, _LogKind, str]]:
    """
    Try to read declaration file content from the installed ``dags`` package path.

    Args:
        files: Callable returned by ``importlib.resources.files`` (see
        ``importlib_resource_files`` at module scope).
        dag_name: DAG folder and file prefix.
        domain: Top-level domain folder under ``dags``.
        ext: File extension (``yml`` or ``yaml``).

    Returns:
        Tuple ``(raw_yaml_text, coerce_source_label, log_kind, log_arg)`` if a file
        was found and read; otherwise ``None``. ``coerce_source_label`` is passed to
        :func:`_coerce_declaration_dict` for warnings.

    Raises:
        Does not raise for missing files; ``FileNotFoundError`` / ``OSError`` per path
        are swallowed here so scanning can continue.
    """
    try:
        resource_path = files("dags").joinpath(
            domain, dag_name, f"{dag_name}_declaration.{ext}"
        )
        if resource_path.is_file():
            content = resource_path.read_text(encoding="utf-8")
            return (
                content,
                f"package:{resource_path}",
                "package",
                resource_path.name,
            )
    except (FileNotFoundError, OSError):
        return None
    return None


def _try_read_declaration_from_s3_volume(
    dag_name: str, domain: str, ext: str
) -> Optional[Tuple[str, str, _LogKind, str]]:
    """
    Try to read declaration YAML text from the Databricks volume / S3 layout.

    Args:
        dag_name: DAG folder and file prefix.
        domain: Top-level domain folder.
        ext: File extension (``yml`` or ``yaml``).

    Returns:
        Same tuple shape as :func:`_try_read_declaration_from_package` when content
        exists; ``None`` if not found or on expected I/O errors.

    Raises:
        Does not raise; unexpected errors are logged and ``None`` is returned.
    """
    relative_path = path.join("dags", domain, dag_name, f"{dag_name}_declaration.{ext}")
    try:
        content = DAGPackagesPathService._read_dag_package_file_from_s3(
            sql_file_relative_path=relative_path,
            engine="databricks_volume",
        )
        if content:
            return (content, f"s3:{relative_path}", "s3", relative_path)
    except (FileNotFoundError, OSError) as e:
        LOGGER.debug("Declaration not found at %s: %s", relative_path, e)
        return None
    except Exception as e:
        LOGGER.warning(
            "Unexpected error loading declaration at %s: %s",
            relative_path,
            e,
        )
        return None
    return None


def _scan_domains_for_declaration(
    try_read: Callable[[str, str], Optional[Tuple[str, str, _LogKind, str]]],
) -> Optional[Dict[str, Any]]:
    """
    Walk ``domain × (yml | yaml)`` and return the first valid declaration mapping.

    Args:
        try_read: Given ``(domain, ext)``, returns file content and log metadata,
            or ``None`` if this candidate path should be skipped.

    Returns:
        Parsed declaration dict, or ``None`` if no candidate produced a valid mapping.
    """
    for domain in _iter_dag_domain_names():
        for ext in ("yml", "yaml"):
            got = try_read(domain, ext)
            if not got:
                continue
            content, coerce_src, log_kind, log_arg = got
            declaration = _coerce_declaration_dict(yaml.safe_load(content), coerce_src)
            if declaration is None:
                continue
            if log_kind == "package":
                LOGGER.info(
                    "Loaded API ingestion declaration from installed package: %s",
                    log_arg,
                )
            else:
                LOGGER.info(
                    "Loaded API ingestion declaration from S3 path: %s",
                    log_arg,
                )
            return declaration
    return None


def _load_from_installed_package(dag_name: str) -> Optional[Dict[str, Any]]:
    """
    Load declaration from the installed bietlejuice package (importlib.resources).

    Declarations are bundled in the wheel via hatch build config in
    ``pyproject.toml`` (same as gsheets declarations and ``*_conf.yml``).
    On Databricks, the wheel is installed as a cluster library, so
    declarations are available from the package.

    Args:
        dag_name: Validated DAG name.

    Returns:
        Declaration mapping if found and valid; ``None`` if ``importlib.resources``
        is unavailable or no file matched.

    Raises:
        Errors other than per-path ``FileNotFoundError`` / ``OSError`` during
        resource access may propagate from ``importlib.resources`` if the package
        layout is invalid.
    """
    if importlib_resource_files is None:
        return None

    def try_read(domain: str, ext: str) -> Optional[Tuple[str, str, _LogKind, str]]:
        return _try_read_declaration_from_package(
            importlib_resource_files, dag_name, domain, ext
        )

    return _scan_domains_for_declaration(try_read)


def _load_from_s3_volume(dag_name: str) -> Optional[Dict[str, Any]]:
    """
    Load declaration by scanning domain folders on S3 / Databricks volume paths.

    Args:
        dag_name: Validated DAG name.

    Returns:
        Declaration mapping if found; ``None`` if scanning failed entirely or
        no valid YAML was found.
    """
    try:

        def try_read(domain: str, ext: str) -> Optional[Tuple[str, str, _LogKind, str]]:
            return _try_read_declaration_from_s3_volume(dag_name, domain, ext)

        return _scan_domains_for_declaration(try_read)
    except Exception as e:
        LOGGER.warning("Could not load declaration from S3/volume: %s", e)
        return None


def load_api_ingestion_declaration(dag_name: str) -> Dict[str, Any]:
    """
    Loads the DAG declaration YAML for the given dag_name.

    Tries in order:
    1. Local filesystem via DAGPackagesPathService.get_dag_path (Composer, local)
    2. Installed package via importlib.resources (Databricks - whl bundles declarations)
    3. S3/volume via DAGPackagesPathService._read_dag_package_file_from_s3 (legacy)

    Args:
        dag_name: The DAG name (e.g., "currency_api")

    Returns:
        The parsed declaration as a dict.

    Raises:
        ValueError: If dag_name contains invalid characters (path traversal prevention)
        FileNotFoundError: If no valid declaration mapping could be resolved from any source
    """
    validate_api_ingestion_dag_name(dag_name)
    dag_path = DAGPackagesPathService.get_dag_path(dag_name)
    if dag_path:
        declaration_path = path.join(dag_path, f"{dag_name}_declaration.yml")
        if path.isfile(declaration_path):
            with open(declaration_path, encoding="utf-8") as f:
                declaration = _coerce_declaration_dict(
                    yaml.safe_load(f), declaration_path
                )
            if declaration is not None:
                LOGGER.info(
                    "Loaded API ingestion declaration from local path: %s",
                    declaration_path,
                )
                return declaration
        yaml_path = path.join(dag_path, f"{dag_name}_declaration.yaml")
        if path.isfile(yaml_path):
            with open(yaml_path, encoding="utf-8") as f:
                declaration = _coerce_declaration_dict(yaml.safe_load(f), yaml_path)
            if declaration is not None:
                LOGGER.info(
                    "Loaded API ingestion declaration from local path: %s",
                    yaml_path,
                )
                return declaration

    declaration = _load_from_installed_package(dag_name)
    if declaration is not None:
        return declaration

    declaration = _load_from_s3_volume(dag_name)
    if declaration is not None:
        return declaration

    raise FileNotFoundError(
        f"Could not load a valid API ingestion declaration for dag_name='{dag_name}'. "
        "Checked local DAG path, installed package, and S3/volume. "
        "Ensure the YAML exists, is a mapping (dict), and the workflow type is api_ingestion."
    )
