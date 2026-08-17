from datetime import date

from bietlejuice.shared.agents.sources import (
    DateColumnFilter,
    PartitionDateFilter,
    SourceCatalog,
    SourceSpec,
    overlapping_calendar_month_bounds,
)


def test_overlapping_calendar_month_bounds_snaps_mid_month_window():
    start, end = overlapping_calendar_month_bounds(date(2026, 8, 12), date(2026, 8, 20))
    assert start == date(2026, 8, 1)
    assert end == date(2026, 8, 31)


def test_overlapping_calendar_month_bounds_spans_year_end():
    start, end = overlapping_calendar_month_bounds(date(2025, 12, 20), date(2026, 1, 5))
    assert start == date(2025, 12, 1)
    assert end == date(2026, 1, 31)


def test_read_prunes_partition_columns_without_leaking_them(spark_session):
    spark_session.createDataFrame(
        [
            (1, "keep", 2026, 7, 15),
            (2, "drop", 2026, 8, 1),
        ],
        ["id", "val", "year", "month", "day"],
    ).createOrReplaceTempView("shared_agents_src_partition")
    catalog = SourceCatalog(date(2026, 7, 10), date(2026, 7, 20), spark=spark_session)
    result = catalog.read(
        SourceSpec(
            table_name="shared_agents_src_partition",
            columns=("id", "val"),
            filter=PartitionDateFilter("year", "month", "day"),
        )
    )

    assert result.columns == ["id", "val"]
    assert {(row.id, row.val) for row in result.collect()} == {(1, "keep")}


def test_read_prunes_date_column_when_it_is_not_projected(spark_session):
    spark_session.createDataFrame(
        [
            (1, "keep", date(2026, 7, 15)),
            (2, "drop", date(2026, 8, 1)),
        ],
        ["id", "val", "dt_event"],
    ).createOrReplaceTempView("shared_agents_src_date")
    catalog = SourceCatalog(date(2026, 7, 10), date(2026, 7, 20), spark=spark_session)
    result = catalog.read(
        SourceSpec(
            table_name="shared_agents_src_date",
            columns=("id", "val"),
            filter=DateColumnFilter("dt_event"),
        )
    )

    assert result.columns == ["id", "val"]
    assert {(row.id, row.val) for row in result.collect()} == {(1, "keep")}
