"""Profiling pipeline: capture fresh-tier metrics and append them to the store.

Called by the post-load profiling Spark job. In one pass it:

1. resolves the runtime gate (:class:`ProfilingConfig`: kill-switch + per-DAG
   opt-in) and no-ops when profiling is inactive;
2. captures table-grain metrics (incl. latest partition *with data*) and
   run-day partition-grain metrics from Delta metadata, fail-open *per
   collector* so one failure never sinks the others;
3. stamps the run's ``year``/``month``/``day`` and appends the rows to
   ``datalake_observability`` (append-only).

Fail-open is intentionally just two layers (NFR1 — a profiling failure must never
break the host DAG): ``_safe`` isolates each collector, and ``run`` guards the
whole pass (config, capture and write) and only logs.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Callable, TypeVar

from pyspark.sql import SparkSession
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.observability.profiling_config import ProfilingConfig
from bietlejuice.observability.profiling.collectors import (
    collect_partition_metrics,
    collect_table_metrics,
)
from bietlejuice.observability.profiling.constants import (
    METRIC_SCHEMA_VERSION,
    CollectionMethod,
)
from bietlejuice.observability.profiling.delta_metadata_reader import (
    DeltaMetadataReader,
)
from bietlejuice.observability.profiling.store_writer import (
    DATABASE,
    ObservabilityStoreWriter,
)
from bietlejuice.services.configuration_service import ConfigurationService

logger = QuintoAndarLogger("ProfilingPipeline")

DATALAKE_BUCKET_CONFIG = "datalake_bucket"

T = TypeVar("T")


class ProfilingPipeline:
    """Captures and persists fresh-tier observability metrics for one table."""

    def __init__(
        self,
        environment: str,
        run_logical_date: str,
        database: str,
        table: str,
        layer: str,
        partitions: list[str] | None = None,
        column_checks: bool = False,  # reserved for future column-level profiling
        dag_enabled: bool | None = None,
        spark: SparkSession = None,
        config_service: ConfigurationService = None,
    ) -> None:
        self.environment = environment
        self.run_logical_date = run_logical_date
        self.database = database
        self.table = table
        self.layer = layer
        self.partitions = partitions or []
        # Reserved for future column-level profiling; unused in fresh-tier capture.
        self.column_checks = column_checks
        self.dag_enabled = dag_enabled
        if spark is None:
            # Imported lazily: importing base_spark eagerly launches a Spark
            # context at import time, which unit tests (no JVM) must not trigger.
            from bietlejuice.base.spark.base_spark import BaseSparkContext

            spark = BaseSparkContext.spark
        self.spark = spark
        self.config_service = config_service or ConfigurationService()

    def run(self) -> None:
        """Capture metrics and append them to the store; fail-open throughout."""
        try:
            self._run()
        except Exception as error:  # fail-open: never break the host DAG (NFR1)
            logger.error(
                f"Profiling pipeline failed for {self.database}.{self.table}: {error}"
            )

    def _run(self) -> None:
        config = ProfilingConfig.from_configuration_service(self.config_service)
        if not config.is_profiling_active(self.dag_enabled):
            logger.info(
                f"Profiling inactive for {self.database}.{self.table}; skipping."
            )
            return

        reader = DeltaMetadataReader(self.spark)
        table_metrics, partition_metrics = self._capture(reader)
        if not table_metrics and not partition_metrics:
            logger.info(
                f"No metrics captured for {self.database}.{self.table}; nothing to write."
            )
            return

        year, month, day = self._partition_parts()
        writer = ObservabilityStoreWriter(self.spark, self._base_location())
        writer.append_table_metrics(
            [
                self._stamp_partitions(record, year, month, day)
                for record in table_metrics
            ]
        )
        writer.append_partition_metrics(
            [
                self._stamp_partitions(record, year, month, day)
                for record in partition_metrics
            ]
        )

    def _capture(
        self, reader: DeltaMetadataReader
    ) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
        """Collect table- and run-day partition-grain records (fail-open per collector).

        Each record is stamped with the common header (incl. ``profiled_at`` and
        the profiled Delta version) so downstream reads are reproducible and
        staleness-aware.
        """
        fqtn = f"{self.database}.{self.table}"
        last_commit = self._safe("last_commit", lambda: reader.last_commit(fqtn), None)
        profiled_delta_version = last_commit.get("version") if last_commit else None
        header = self._build_header(profiled_delta_version)

        table_record = self._safe(
            "table_metrics",
            lambda: {
                **header,
                **collect_table_metrics(reader, self.database, self.table),
            },
            None,
        )
        partition_columns = (
            table_record.get("partition_columns") if table_record else []
        )
        partition_records = self._safe(
            "partition_metrics",
            lambda: [
                {**header, **record}
                for record in collect_partition_metrics(
                    reader,
                    self.database,
                    self.table,
                    partition_columns,
                    last_commit,
                    self.run_logical_date,
                )
            ],
            [],
        )
        return (
            [table_record] if table_record else [],
            partition_records or [],
        )

    def _build_header(self, profiled_delta_version: Any) -> dict[str, Any]:
        return {
            "database": self.database,
            "table": self.table,
            "layer": self.layer,
            "environment": self.environment,
            "run_logical_date": self.run_logical_date,
            "profiled_delta_version": profiled_delta_version,
            "profiled_at": datetime.now(timezone.utc),
            "collection_method": CollectionMethod.SPARK_LOG.value,
            "metric_schema_version": METRIC_SCHEMA_VERSION,
        }

    @staticmethod
    def _stamp_partitions(
        record: dict[str, Any], year: int, month: int, day: int
    ) -> dict[str, Any]:
        return {**record, "year": year, "month": month, "day": day}

    def _safe(self, name: str, function: Callable[[], T], default: T) -> T:
        """Run a collector, swallowing and logging any failure (fail-open)."""
        try:
            return function()
        except Exception as error:  # one collector must not sink the others
            logger.error(f"Profiling collector '{name}' failed: {error}")
            return default

    def _base_location(self) -> str:
        bucket = self.config_service.get_config(DATALAKE_BUCKET_CONFIG)
        return f"s3://{bucket}/{DATABASE}"

    def _partition_parts(self) -> tuple[int, int, int]:
        """Derive year/month/day partitions from the run's logical date."""
        parsed = datetime.strptime(self.run_logical_date, "%Y-%m-%d")
        return parsed.year, parsed.month, parsed.day
