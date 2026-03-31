"""
Resolves EMR vs Databricks cluster utilities.

Databricks continues to use native ``dbutils`` / ``DBUtils``; EMR uses
:class:`AwsEmrClusterUtils` with a compatible ``.secrets`` / ``.fs`` surface.
"""

from __future__ import annotations

from typing import Any, Optional

from bietlejuice.base.spark.runtime_detector import RuntimeDetector

_emr_dbutils_facade: Optional[Any] = None


def get_emr_dbutils_facade() -> Any:
    """
    Singleton ``AwsEmrClusterUtils`` instance (dbutils-compatible API).

    Used when ``SPARK_RUNTIME=emr``.
    """
    global _emr_dbutils_facade
    if _emr_dbutils_facade is None:
        # Lazy import: avoids loading boto3 on Databricks when only
        # ``should_use_emr_cluster_utils`` / ``RuntimeDetector`` are used.
        from bietlejuice.base.spark.cluster_utils.aws_emr_cluster_utils import (
            AwsEmrClusterUtils,
        )

        _emr_dbutils_facade = AwsEmrClusterUtils()
    return _emr_dbutils_facade


def should_use_emr_cluster_utils() -> bool:
    # SPARK_RUNTIME=emr is set on EMR clusters (see prod/forno spark_env_vars).
    return RuntimeDetector.is_emr()


def reset_emr_dbutils_facade() -> None:
    """Clear cached EMR facade (for tests)."""
    global _emr_dbutils_facade
    _emr_dbutils_facade = None
