"""Astro-dev DAG-processor pre-warm (parse-time optimization).

Airflow 2.x forks a child process per DAG file. Only ``airflow.*`` modules are
pre-imported in the manager (``scheduler.parsing_pre_import_modules``). Every
parse therefore re-executes the full bietlejuice import graph.

This module is imported by every Airflow process at ``settings.initialize()``
(via ``$AIRFLOW_HOME/config`` on ``sys.path``). We warm the builder stack and
the global ``ConfigurationService`` **once in the dag-processor / scheduler
manager** so forked children inherit warm ``sys.modules`` and the class-level
config cache (copy-on-write).

Gate:
  - Default: warm only when argv indicates ``dag-processor`` or ``scheduler``.
  - Override: ``BIETLEJUICE_PREWARM=always|never``.

Safe to import before the DAGs folder is on ``sys.path`` — only image-installed
packages are imported (bietlejuice lives in site-packages on the Astro image).
"""

from __future__ import annotations

import logging
import os
import sys
import time
from math import isfinite
from pathlib import Path
from typing import Iterable, List, Sequence, Tuple

_LOG = logging.getLogger("bietlejuice.prewarm")

# Heavy modules imported by every DAG Builder ``*_dag.py``. Order matters only
# for readability; importlib caches by name.
_PREWARM_MODULES: Sequence[str] = (
    # Third-party paid on first builder import
    "pydantic",
    "cerberus",
    "yaml",
    # Builder entry graph (transitively pulls factories, workflows, task creators)
    "bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser",
    "bietlejuice.base.airflow.dag_builders.main_builder.factories.factory_dispatcher",
    "bietlejuice.base.airflow.task_creators.task_creator_factory",
    "bietlejuice.base.airflow.datasets.dataset_adder",
    "bietlejuice.base.pipeline",
    "bietlejuice.base.validation.cluster_args",
    "bietlejuice.services.configuration_service",
    # Operators used when building task graphs
    "databricks_plugin",
    "emr_plugin",
    # Reached only after a DAG is built/serialized, so generated DAG imports
    # do not give parsing_pre_import_modules a chance to warm these.
    "airflow.models.dagbag",
    "airflow.models.serialized_dag",
    "airflow.serialization.serialized_objects",
    "airflow.www.security_appless",
)

# Deliberately not warmed:
# - pandas/numpy: absent from the DAG Builder parse path.
# - per-DAG confs, declarations, and paths: DAG-only deploys can change them.
# - ``dags``: Airflow adds DAGS_FOLDER to sys.path after local settings import.


def _prewarm_override() -> str | None:
    raw = os.environ.get("BIETLEJUICE_PREWARM", "").strip().lower()
    return raw or None


def _should_prewarm(argv: Iterable[str] | None = None) -> bool:
    override = _prewarm_override()
    if override == "never":
        return False
    if override == "always":
        return True

    tokens = [t.lower() for t in (argv if argv is not None else sys.argv)]
    joined = " ".join(tokens)
    # Skip non-parsing processes even if argv is ambiguous.
    if any(t in joined for t in ("webserver", "api-server", "worker", "triggerer")):
        return False
    # Astro / standalone dag-processor and classic scheduler (embeds parsing).
    return (
        "dag-processor" in joined
        or "dag_processor" in joined
        or "scheduler" in joined
    )


def _import_module(name: str) -> Tuple[str, bool, str | None]:
    try:
        __import__(name)
        return name, True, None
    except Exception as exc:  # noqa: BLE001 — must not crash Airflow startup
        return name, False, f"{type(exc).__name__}: {exc}"


def _libyaml_available() -> bool:
    try:
        import yaml

        return bool(getattr(yaml, "__with_libyaml__", False))
    except Exception:  # noqa: BLE001
        return False


def _install_fast_yaml_loader() -> str:
    """Point ``yaml.safe_load`` / ``SafeLoader`` at libyaml when available.

    ``hierarchical_conf`` (and other third-party callers) use ``yaml.safe_load``
    which stays on the pure-Python loader even when libyaml is installed.
    Rebinding keeps their call sites fast without forking the dependency.
    """
    try:
        import yaml
    except Exception as exc:  # noqa: BLE001
        return f"skipped ({type(exc).__name__}: {exc})"

    c_safe = getattr(yaml, "CSafeLoader", None)
    if c_safe is None:
        return "unavailable (no CSafeLoader)"

    def _safe_load(stream):
        return yaml.load(stream, Loader=c_safe)

    yaml.SafeLoader = c_safe  # type: ignore[misc, assignment]
    yaml.safe_load = _safe_load  # type: ignore[assignment]
    return "installed"


def _warm_configuration_service() -> str:
    """Load global prod/forno conf once into ConfigurationService._instance_cache."""
    try:
        from bietlejuice.services.configuration_service import (
            ConfigurationService,
            WONKA_SHARED_CONFIG_DAG_NAME,
        )

        # dag_name=None → only BIETLEJUICE_CONFIG_ROOT (image-baked prod_conf.yml).
        # Force HierarchicalConf I/O now (ConfigurationService defers until get_config).
        cfg = ConfigurationService()
        cfg.get_config("datalake_bucket")  # triggers _ensure_config_loaded (YAML I/O)
        # Wonka registry factory builds ~271 DAGs that all share this sentinel key.
        # Warm it in the manager so forked parse children inherit the loaded conf.
        wonka_cfg = ConfigurationService(WONKA_SHARED_CONFIG_DAG_NAME)
        wonka_cfg.get_config("datalake_bucket")
        return "ok"
    except Exception as exc:  # noqa: BLE001
        return f"skipped ({type(exc).__name__}: {exc})"


def _warm_airflow_plugins() -> tuple[str, int]:
    """Load Airflow entry-point plugins once for all forked parse children."""
    try:
        from airflow import plugins_manager

        plugins_manager.ensure_plugins_loaded()
        return "ok", len(plugins_manager.plugins or [])
    except Exception as exc:  # noqa: BLE001
        return f"skipped ({type(exc).__name__}: {exc})", 0


def _warm_line_folders() -> tuple[str, int]:
    """Cache top-level DAG domains, but never mutable per-DAG paths."""
    try:
        from bietlejuice.base.service.dag_packages_path_service import (
            DAGPackagesPathService,
        )

        folders = DAGPackagesPathService._get_line_folders()
        return "ok", len(folders)
    except Exception as exc:  # noqa: BLE001
        return f"skipped ({type(exc).__name__}: {exc})", 0


def _declaration_prewarm_timeout(timeout_s: float | None) -> float:
    """Return a valid soft timeout without violating the never-raise contract."""
    raw_timeout = (
        timeout_s
        if timeout_s is not None
        else os.environ.get("BIETLEJUICE_PREWARM_DECLARATIONS_TIMEOUT_S", "120")
    )
    try:
        parsed_timeout = float(raw_timeout)
    except (TypeError, ValueError):
        parsed_timeout = 120.0
        _LOG.warning(
            "Invalid BIETLEJUICE_PREWARM_DECLARATIONS_TIMEOUT_S=%r; using 120s",
            raw_timeout,
        )
    if not isfinite(parsed_timeout) or parsed_timeout <= 0:
        _LOG.warning(
            "Non-positive/non-finite declaration prewarm timeout=%r; using 120s",
            raw_timeout,
        )
        return 120.0
    return parsed_timeout


def _warm_dag_declarations(
    timeout_s: float | None = None,
) -> tuple[str, int, int, float]:
    """Warm content-hash-keyed declarations within a soft cumulative time budget.

    The budget is checked between local-file parses; it intentionally does not
    interrupt an in-flight YAML/Cerberus call because asynchronous interruption
    could leave locks or library state unsafe for the subsequent fork.
    """
    if (
        os.environ.get("BIETLEJUICE_PREWARM_DECLARATIONS", "").strip().lower()
        == "never"
    ):
        return "disabled", 0, 0, 0.0

    timeout_s = _declaration_prewarm_timeout(timeout_s)

    started = time.perf_counter()
    warmed = 0
    failed = 0
    try:
        from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser import (
            DAGYamlParser,
        )
        from bietlejuice.base.service.dag_packages_path_service import (
            DAGPackagesPathService,
        )

        declaration_paths = []
        for line_folder in DAGPackagesPathService._get_line_folders():
            line_path = Path(line_folder.path)
            declaration_paths.extend(line_path.rglob("*_declaration.yml"))
            declaration_paths.extend(line_path.rglob("*_declaration.yaml"))

        for declaration_path in sorted(declaration_paths):
            elapsed = time.perf_counter() - started
            if elapsed >= timeout_s:
                return "timeout", warmed, failed, round(elapsed, 3)

            dag_name = declaration_path.name.rsplit("_declaration.", 1)[0]
            try:
                DAGYamlParser(dag_name).dag_declaration()
                warmed += 1
            except Exception:  # noqa: BLE001 — one invalid DAG must not block startup
                failed += 1
                _LOG.debug(
                    "Declaration pre-warm failed for %s",
                    dag_name,
                    exc_info=True,
                )
    except Exception as exc:  # noqa: BLE001 — must not crash Airflow startup
        elapsed = time.perf_counter() - started
        return (
            f"skipped ({type(exc).__name__}: {exc})",
            warmed,
            failed,
            round(elapsed, 3),
        )

    elapsed = time.perf_counter() - started
    status = "ok" if failed == 0 else "partial"
    return status, warmed, failed, round(elapsed, 3)


def prewarm_bietlejuice(modules: Sequence[str] | None = None) -> dict:
    """Import builder modules and warm global ConfigurationService.

    Returns a summary dict for tests / logging. Never raises.
    """
    started = time.perf_counter()
    yaml_shim = _install_fast_yaml_loader()
    target = list(modules) if modules is not None else list(_PREWARM_MODULES)
    imported: List[str] = []
    failed: List[Tuple[str, str]] = []

    for name in target:
        mod, ok, err = _import_module(name)
        if ok:
            imported.append(mod)
        else:
            failed.append((mod, err or "unknown"))

    plugin_status, plugin_count = _warm_airflow_plugins()
    line_folder_status, line_folder_count = _warm_line_folders()
    conf_status = _warm_configuration_service()
    (
        declaration_status,
        declaration_count,
        declaration_failures,
        declaration_elapsed_s,
    ) = _warm_dag_declarations()
    elapsed = time.perf_counter() - started
    libyaml = _libyaml_available()

    summary = {
        "imported": imported,
        "failed": failed,
        "configuration_service": conf_status,
        "plugins": plugin_status,
        "plugin_count": plugin_count,
        "line_folders": line_folder_status,
        "line_folder_count": line_folder_count,
        "declarations": declaration_status,
        "declaration_count": declaration_count,
        "declaration_failures": declaration_failures,
        "declaration_elapsed_s": declaration_elapsed_s,
        "yaml_shim": yaml_shim,
        "libyaml": libyaml,
        "elapsed_s": round(elapsed, 3),
    }

    fail_msg = (
        f", failed={len(failed)} ({', '.join(n for n, _ in failed)})" if failed else ""
    )
    _LOG.info(
        "bietlejuice pre-warm complete: modules=%d%s, plugins=%s(%d), "
        "line_folders=%s(%d), declarations=%s(%d, failed=%d, %.3fs), "
        "conf=%s, yaml_shim=%s, libyaml=%s, elapsed=%.3fs",
        len(imported),
        fail_msg,
        plugin_status,
        plugin_count,
        line_folder_status,
        line_folder_count,
        declaration_status,
        declaration_count,
        declaration_failures,
        declaration_elapsed_s,
        conf_status,
        yaml_shim,
        libyaml,
        elapsed,
    )
    return summary


# Run at import time when this module is loaded as airflow_local_settings.
if _should_prewarm():
    prewarm_bietlejuice()
else:
    _LOG.debug(
        "bietlejuice pre-warm skipped (process argv=%r, BIETLEJUICE_PREWARM=%r)",
        sys.argv,
        _prewarm_override(),
    )
