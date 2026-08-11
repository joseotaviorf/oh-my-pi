"""Shared bi-etl-ejuice repo root discovery and document_parser bootstrap."""

from __future__ import annotations

import importlib.util
import sys
from functools import cache
from pathlib import Path
from types import ModuleType

_PARSER_MOD_NAME = "tars_evals_document_parser"
_PARSER_RELPATH = Path(
    "dags/governance/datahub_business_context/sync/document_parser.py"
)
_PKG_PARENT_RELPATH = Path("dags/governance/datahub_business_context")


def _discover_repo_root(start: Path) -> Path:
    here = start.resolve()
    for candidate in [here.parent, *here.parents]:
        if (candidate / "docs" / "llm_context").is_dir():
            return candidate
    raise RuntimeError(
        "repo root discovery failed: no docs/llm_context above "
        f"{here}. Expected packages/tars-evals inside bi-etl-ejuice."
    )


@cache
def repo_root() -> Path:
    return _discover_repo_root(Path(__file__))


@cache
def load_document_parser() -> ModuleType:
    """Live-import the repo's hydration parser under a stable module name.

    ``document_parser`` does ``from sync.constants import ...``; put its package
    parent on ``sys.path`` so that relative-by-name import resolves. Register in
    ``sys.modules`` before exec so ``from __future__ import annotations``
    dataclasses can resolve string annotations via ``sys.modules[cls.__module__]``.
    """
    root = repo_root()
    path = root / _PARSER_RELPATH
    if not path.is_file():
        raise RuntimeError(
            f"document_parser not found at {path}. "
            "Expected dags/governance/datahub_business_context/sync/"
            "document_parser.py under the bi-etl-ejuice repo root."
        )
    pkg_parent = root / _PKG_PARENT_RELPATH
    if str(pkg_parent) not in sys.path:
        sys.path.insert(0, str(pkg_parent))
    if _PARSER_MOD_NAME in sys.modules:
        return sys.modules[_PARSER_MOD_NAME]
    spec = importlib.util.spec_from_file_location(_PARSER_MOD_NAME, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"unable to load document_parser from {path}")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[_PARSER_MOD_NAME] = mod
    try:
        spec.loader.exec_module(mod)
    except Exception:
        if sys.modules.get(_PARSER_MOD_NAME) is mod:
            sys.modules.pop(_PARSER_MOD_NAME, None)
        raise
    return mod
