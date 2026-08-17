"""Pruned lake-table reader for agent Spark jobs.

This module only decides **which lake rows to load**. Callers own table
inventory (``SourceSpec`` values) and any later business-time filters.

Scan window is the overlapping calendar months of ``load_start_date`` /
``load_end_date``, plus optional lag/extension on the filter. Mid-month
reruns still read full months of partitions.
"""

from __future__ import annotations

import calendar
from dataclasses import dataclass
from datetime import date, timedelta
from typing import Dict, Optional, Tuple, Union

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F


def overlapping_calendar_month_bounds(
    load_start_date: date,
    load_end_date: date,
) -> Tuple[date, date]:
    """First day of ``load_start_date``'s month through last day of ``load_end_date``'s month."""
    month_start = load_start_date.replace(day=1)
    last_day = calendar.monthrange(load_end_date.year, load_end_date.month)[1]
    month_end = load_end_date.replace(day=last_day)
    return month_start, month_end


@dataclass(frozen=True)
class PartitionDateFilter:
    """Prune Hive/Delta partitions via reconstructed ``year``/``month``/``day``.

    Lower bound is the overlapping-month start. Upper bound is overlapping-month
    end plus ``update_lag_days``.

    Use ``update_lag_days`` when partition columns follow a late-arriving
    clock (e.g. ``ts_updated``) rather than event time.
    """

    year_column: str
    month_column: str
    day_column: str
    update_lag_days: int = 0


@dataclass(frozen=True)
class DateColumnFilter:
    """Prune rows on a real date column (not year/month/day partitions).

    Same month-snapped window as ``PartitionDateFilter``.
    ``end_date_extension_days`` widens only the upper bound.
    """

    date_column: str
    end_date_extension_days: int = 0


SourceFilter = Union[PartitionDateFilter, DateColumnFilter]


def _filter_column_names(source_filter: SourceFilter) -> Tuple[str, ...]:
    if isinstance(source_filter, PartitionDateFilter):
        return (
            source_filter.year_column,
            source_filter.month_column,
            source_filter.day_column,
        )
    if isinstance(source_filter, DateColumnFilter):
        return (source_filter.date_column,)
    raise TypeError(f"Unsupported source filter type: {type(source_filter)!r}")


@dataclass(frozen=True)
class SourceSpec:
    """One source table: ``schema.table`` name, columns to project, optional prune filter.

    ``filter=None`` loads the projected columns with no date window
    (used for small unpartitioned tables).
    """

    table_name: str
    columns: Tuple[str, ...]
    filter: Optional[SourceFilter] = None


class SourceCatalog:
    """Lazy, cached reader. Specs come from callers; this class does not own them.

    ``load_start_date`` / ``load_end_date`` are snapped to overlapping calendar
    months for prune only. ``read(spec)`` is the only public entry point.
    """

    def __init__(
        self,
        load_start_date: date,
        load_end_date: date,
        spark: Optional[SparkSession] = None,
    ) -> None:
        self._scan_start, self._scan_end = overlapping_calendar_month_bounds(
            load_start_date,
            load_end_date,
        )
        self._spark = spark
        self._read_cache: Dict[SourceSpec, DataFrame] = {}

    def _require_spark(self) -> SparkSession:
        """Fail fast when a catalog was built without a session (unit stubs)."""
        if self._spark is None:
            raise ValueError("SparkSession is required to read source tables")
        return self._spark

    def _apply_filter(
        self,
        projection: DataFrame,
        source_filter: SourceFilter,
    ) -> DataFrame:
        """Restrict ``projection`` to the source-scan window for this job."""
        if isinstance(source_filter, PartitionDateFilter):
            partition_day = F.make_date(
                F.col(source_filter.year_column),
                F.col(source_filter.month_column),
                F.col(source_filter.day_column),
            )
            upper_bound = self._scan_end + timedelta(days=source_filter.update_lag_days)
            return projection.filter(
                (partition_day >= F.lit(self._scan_start))
                & (partition_day <= F.lit(upper_bound))
            )

        if isinstance(source_filter, DateColumnFilter):
            upper_bound = self._scan_end + timedelta(
                days=source_filter.end_date_extension_days
            )
            return projection.filter(
                (F.col(source_filter.date_column) >= F.lit(self._scan_start))
                & (F.col(source_filter.date_column) <= F.lit(upper_bound))
            )

        raise TypeError(f"Unsupported source filter type: {type(source_filter)!r}")

    def read(self, spec: SourceSpec) -> DataFrame:
        """Load ``spec.table_name``, project ``spec.columns``, apply prune filter.

        Repeated ``read`` of the same ``SourceSpec`` in one catalog instance
        returns the cached DataFrame (same Spark plan, no second scan setup).
        """
        if spec in self._read_cache:
            return self._read_cache[spec]

        session = self._require_spark()
        table = session.table(spec.table_name)
        if spec.filter is None:
            dataframe = table.select(*spec.columns)
        else:
            extra = [
                column
                for column in _filter_column_names(spec.filter)
                if column not in spec.columns
            ]
            projection = table.select(*spec.columns, *extra)
            dataframe = self._apply_filter(projection, spec.filter)
            if extra:
                dataframe = dataframe.drop(*extra)
        self._read_cache[spec] = dataframe
        return dataframe
