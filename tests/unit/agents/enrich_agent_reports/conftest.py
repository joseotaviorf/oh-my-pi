"""Shared PySpark pytest fixtures for enrich_agent_reports Spark job tests.

Sessions are module-scoped and use local[1] for fast unit evaluation of Column logic.

Run::

    pytest tests/unit/agents/enrich_agent_reports/ -q

Keeps a tight set of Spark Column regression tests for agent_reports jobs (not full ETL coverage).
"""
import pytest
from pyspark.sql import SparkSession


@pytest.fixture(scope="module")
def spark():
    """Local SparkSession shared across all tests in this module.

    Uses getOrCreate() so it cooperates with session-scoped fixtures from other
    conftest files (e.g. qube/conftest.py) when the full test suite runs together.
    The session is intentionally NOT stopped here to avoid interfering with
    session-scoped fixtures in sibling test directories.
    """
    return (
        SparkSession.builder.appName("test_enrich_agent_reports")
        .master("local[1]")
        .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse")
        .config("spark.ui.enabled", "false")
        .getOrCreate()
    )
