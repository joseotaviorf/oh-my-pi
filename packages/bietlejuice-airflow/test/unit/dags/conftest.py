"""Shared fixtures for tests that import modules under repo-root ``dags/``."""

import os
import sys
from pathlib import Path

# Hand-written DAG modules load forno_conf/prod_conf via ConfigurationService at
# import time. CI does not export ENVIRONMENT; ensure a default before collection
# imports any test module that loads a DAG (e.g. for_rent/vocs_machina_planning).
os.environ.setdefault("ENVIRONMENT", "forno")

_REPO_ROOT = Path(__file__).resolve().parents[5]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))
