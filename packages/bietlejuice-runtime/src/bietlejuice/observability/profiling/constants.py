"""Constants and enums for the data profiling & observability collection layer.

The store schemas are documented in
dags/governance/data_observability/metadata/raw/*.yml.
"""

from __future__ import annotations

from enum import Enum

# Bumped when the metric row shape changes, so historical readers can adapt.
METRIC_SCHEMA_VERSION = 1


class CollectionMethod(Enum):
    """Provenance of a measurement, persisted on every metric row."""

    SPARK_LOG = "spark_log"
