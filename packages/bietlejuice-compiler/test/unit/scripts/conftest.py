import sys
from pathlib import Path

_COMPILER_ROOT = Path(__file__).resolve().parents[3]
if str(_COMPILER_ROOT) not in sys.path:
    sys.path.insert(0, str(_COMPILER_ROOT))
