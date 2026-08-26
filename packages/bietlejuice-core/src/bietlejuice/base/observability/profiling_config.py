"""Opt-in / kill-switch gate for the post-load profiling task.

Lives in ``bietlejuice-core`` because it is consulted in two runtimes:

* at DAG-build/parse time by ``BaseWorkflow._check_include_profiling_task`` (in
  ``bietlejuice-airflow``, which depends on core but not on the Databricks-side
  ``bietlejuice-runtime``);
* at execution time by the profiling Spark job (``bietlejuice-runtime``), as a
  defence-in-depth re-check of the runtime kill-switch.

Rollout model (see the RFC "Concrete names & decisions"):

* ``profiling_enabled`` — global kill-switch (default True). When False, nothing
  is collected anywhere, without a deploy.
* ``profiling_default_enabled`` — how an *absent* ``observability`` block is
  treated. Phase 1 (initial prod) = False, so a DAG is profiled only when it
  explicitly opts in. Phase 2 = flip to True (profiling becomes opt-out).
* ``dag_enabled`` — the per-DAG ``observability: {enabled: ...}`` declaration,
  passed in per capture; ``None`` means the DAG did not declare the block.
* Optional ``observability.tables`` (handled at DAG-build time, not here) is a
  clean-table allowlist so a large CDC DAG can opt in a subset of tables.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from quintoandar_logger import QuintoAndarLogger

if TYPE_CHECKING:
    from bietlejuice.services.configuration_service import ConfigurationService

logger = QuintoAndarLogger("ProfilingConfig")

KILL_SWITCH_KEY = "profiling_enabled"
DEFAULT_ENABLED_KEY = "profiling_default_enabled"

_TRUTHY = {"true", "1", "yes"}


class ProfilingConfig:
    """Resolves whether the profiling task should run for a given DAG."""

    def __init__(self, kill_switch: bool = True, default_enabled: bool = False) -> None:
        self.kill_switch = kill_switch
        self.default_enabled = default_enabled

    @classmethod
    def from_configuration_service(
        cls, configuration_service: ConfigurationService
    ) -> ProfilingConfig:
        """Build the gate from the DAG's resolved configuration, fail-open to defaults."""
        return cls(
            kill_switch=_read_bool(
                configuration_service, KILL_SWITCH_KEY, default=True
            ),
            default_enabled=_read_bool(
                configuration_service, DEFAULT_ENABLED_KEY, default=False
            ),
        )

    def is_profiling_active(self, dag_enabled: bool | None = None) -> bool:
        """True only when the kill-switch is on and the DAG is opted in.

        When the DAG did not declare ``observability`` (``dag_enabled is None``),
        the global ``default_enabled`` decides (Phase 1 = off, Phase 2 = on).
        """
        if not self.kill_switch:
            return False
        if dag_enabled is None:
            return self.default_enabled
        return dag_enabled


def _read_bool(
    configuration_service: ConfigurationService, key: str, default: bool
) -> bool:
    """Read a boolean-ish config value, defaulting when the key is absent."""
    try:
        value = configuration_service.get_config(key)
    except Exception as error:  # config key may be absent; fail-open to default
        logger.info(f"Config '{key}' not found ({error}); using default {default}.")
        return default
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in _TRUTHY
