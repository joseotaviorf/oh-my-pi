"""Module mocks for monalisa_capta_ai_evaluations spark job tests.

The job imports Databricks-side bietlejuice modules at import time; mock them so
``main()`` can be exercised without a cluster.
"""

import os
import sys
from unittest.mock import MagicMock

_BIETLEJUICE_MOCKS = [
    "bietlejuice",
    "bietlejuice.base",
    "bietlejuice.base.db",
    "bietlejuice.base.pipeline",
    "bietlejuice.base.pipeline.layer_enum",
    "bietlejuice.base.spark",
    "bietlejuice.base.spark.delta_secondary_catalog_sync",
    "bietlejuice.base.validation",
    "bietlejuice.base.validation.spark_args",
    "bietlejuice.loaders",
    "bietlejuice.loaders.delta_loader",
    "bietlejuice.services",
    "bietlejuice.services.configuration_service",
    "quintoandar_logger",
]
for _mod in _BIETLEJUICE_MOCKS:
    sys.modules.setdefault(_mod, MagicMock())

os.environ.setdefault("PYSPARK_PYTHON", sys.executable)
