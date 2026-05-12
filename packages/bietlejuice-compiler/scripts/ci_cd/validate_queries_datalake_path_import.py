"""Fail if QUERIES_DATALAKE_PATH is imported from bietlejuice.base.db.

That constant lives in bietlejuice.base.paths; importing it from .db is wrong and
broke on namespace-package installs.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[4]  # .../bi-etl-ejuice
_BAD = re.compile(
    r"from\s+bietlejuice\.base\.db\s+import\s+"
    r"(?P<names>[^\n#]+?)\s*(?:#.*)?$",
    re.MULTILINE,
)
_TARGET = "QUERIES_DATALAKE_PATH"


def _imports_queries_from_db(stmt: str) -> bool:
    names = stmt.split()
    for i, t in enumerate(names):
        if t in (",", "("):
            continue
        if t == _TARGET or t == _TARGET + ",":
            return True
    return False


def _py_files_to_scan() -> list[Path]:
    out: list[Path] = []
    dags = _REPO_ROOT / "dags"
    if dags.is_dir():
        out.extend(f for f in dags.rglob("*.py") if f.is_file())
    for name in (
        "bietlejuice-core",
        "bietlejuice-runtime",
        "bietlejuice-compiler",
        "bietlejuice-airflow",
    ):
        src = _REPO_ROOT / "packages" / name / "src"
        if src.is_dir():
            out.extend(f for f in src.rglob("*.py") if f.is_file())
    return out


def main() -> int:
    bad_files: list[str] = []
    for f in _py_files_to_scan():
        try:
            text = f.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for m in _BAD.finditer(text):
            if _imports_queries_from_db(m.group("names").strip()):
                rel = f.relative_to(_REPO_ROOT)
                bad_files.append(str(rel))
                break

    if bad_files:
        print(
            "QUERIES_DATALAKE_PATH must be imported from "
            "bietlejuice.base.paths, not bietlejuice.base.db:\n  "
            + "\n  ".join(sorted(bad_files)),
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
