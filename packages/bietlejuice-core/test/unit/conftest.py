import sys
from types import ModuleType
from unittest.mock import MagicMock

# Stub the monorepo `dags` package so production code that does
# `from dags import DAG_PACKAGES_ROOT` (lazy import) or `dags.__file__`
# (in bietlejuice.base.paths._find_dag_packages_root) doesn't fail when
# running standalone unit tests outside the full repo context.
#
# Use a real ModuleType — not MagicMock — because MagicMock.__getattr__
# explicitly raises AttributeError for magic attributes like __file__.
_dags_stub = ModuleType("dags")
_dags_stub.__file__ = "/tmp/dags/__init__.py"
_dags_stub.__path__ = ["/tmp/dags"]
_dags_stub.DAG_PACKAGES_ROOT = "/tmp/dags"  # type: ignore[attr-defined]
sys.modules.setdefault("dags", _dags_stub)

# Stub private Nexus packages not available in the local dev environment.
# These are only needed at runtime inside Databricks/Composer, not in unit tests.
for _private_pkg in [
    "databricks_plugin",
    "databricks_plugin.hooks",
    "databricks_plugin.hooks.databricks_hook",
    "extra_link_plugin",
    "quintoandar_logger",
]:
    sys.modules.setdefault(_private_pkg, MagicMock())
