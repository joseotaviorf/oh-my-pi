"""
Detects the Spark runtime environment (Databricks vs EMR).

Used by ``CatalogStrategyResolver`` to decide which secondary metastore
service to activate:

- **Databricks** → secondary is Glue (boto3)
- **EMR** → secondary is Unity Catalog (REST API)

Detection relies on the ``SPARK_RUNTIME`` environment variable, which
must be set at the cluster level (``spark_env_vars`` in conf YAML).
"""

from __future__ import annotations

import os
from typing import Optional

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("RuntimeDetector")


class RuntimeDetector:
    """Detect whether the current Spark session is running on Databricks or
    EMR via the ``SPARK_RUNTIME`` environment variable.

    Expected values: ``databricks`` | ``emr``.
    Set in the cluster configuration (``spark_env_vars`` / ``spark.driverEnv`` /
    ``spark.executorEnv`` / ``spark.yarn.appMasterEnv``).
    """

    _DATABRICKS = "databricks"
    _EMR = "emr"

    _VALID_RUNTIMES = (_DATABRICKS, _EMR)

    @staticmethod
    def _detected_runtime() -> Optional[str]:
        raw = os.environ.get("SPARK_RUNTIME")
        if raw is None:
            logger.warning(
                "m=_detected_runtime, msg=SPARK_RUNTIME env var is not set. "
                "Secondary catalog sync will be skipped. "
                "Set it in the cluster config (spark_env_vars / spark.yarn.appMasterEnv)."
            )
            return None
        runtime = raw.lower().strip()
        if runtime not in RuntimeDetector._VALID_RUNTIMES:
            logger.warning(
                f"m=_detected_runtime, SPARK_RUNTIME='{raw}', "
                f"msg=unrecognized value, expected one of {RuntimeDetector._VALID_RUNTIMES}. "
                "Secondary catalog sync will be skipped."
            )
            return None
        return runtime

    @staticmethod
    def is_databricks() -> bool:
        return RuntimeDetector._detected_runtime() == RuntimeDetector._DATABRICKS

    @staticmethod
    def is_emr() -> bool:
        return RuntimeDetector._detected_runtime() == RuntimeDetector._EMR

    @staticmethod
    def runtime_name() -> str:
        """Return a human-readable label for logging."""
        return RuntimeDetector._detected_runtime() or "unknown"
