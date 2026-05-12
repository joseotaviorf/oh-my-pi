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

# Stub bietlejuice-runtime's SchemaValidator so ci_cd scripts that import it
# can be loaded in the compiler's standalone test environment.
_schema_validator_mock = MagicMock()
_schema_validator_mock.SchemaValidator.VALID_SCHEMA_TYPES = [
    "string",
    "bigint",
    "int",
    "double",
    "boolean",
    "date",
    "timestamp",
    "decimal",
]

sys.modules.setdefault("bietlejuice.base.core_models", MagicMock())
sys.modules.setdefault("bietlejuice.base.core_models.helpers", MagicMock())
sys.modules.setdefault(
    "bietlejuice.base.core_models.helpers.schema_validator", _schema_validator_mock
)
