"""Ensure ``emr`` is importable when running pytest from the repo root."""

import sys
from pathlib import Path

_emr_src = Path(__file__).resolve().parents[2] / "src"
if str(_emr_src) not in sys.path:
    sys.path.insert(0, str(_emr_src))
