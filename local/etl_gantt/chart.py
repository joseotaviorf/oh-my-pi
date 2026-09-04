"""Plotly Gantt of latest-run bars in real UTC time, with median markers."""

from __future__ import annotations

from collections.abc import Iterator
from datetime import date, datetime, time, timedelta
from typing import Any, Literal

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

_EPOCH_DATE = date(2000, 1, 1)
# Fractions of a y-category band, so bars and median ticks scale together.
_BAR_WIDTH = 0.7
_MEDIAN_HEIGHT_RATIO = 0.7
_MEDIAN_HOVER_SIZE = 18
_ROW_HEIGHT_PX = 28
_CHART_HEIGHT_MIN = 280
_CHART_HEIGHT_MAX = 1600
_CHART_HEIGHT_PAD = 140
# Same day first, so a median equidistant from both sides of its bar stays put.
_DAY_SHIFTS = (0, -1, 1)
_HOURLY_TICK_SPAN = timedelta(days=2)
_MIDNIGHT_LINE_SPAN = timedelta(days=7)
_AXIS_TITLE = "Run time (UTC)"
_IDLE_MIN_GAP_DEFAULT = timedelta(minutes=15)
_IDLE_COLOR = "#f2c744"
_IDLE_OPACITY = 0.15
_IDLE_LEGEND_NAME = "No dependency running"


def build_gantt_figure(
    frame: pd.DataFrame,
    idle_min_gap: timedelta = _IDLE_MIN_GAP_DEFAULT,
    color_by: Literal["owner", "hop", "dag"] = "owner",
) -> go.Figure:
    """Build a Gantt of latest start→end bars in UTC, with median ticks."""
    prepared = _prepare_rows(frame)
    if prepared.empty:
        fig = go.Figure()
        fig.update_layout(
            title="ETL Gantt (no latest-run timestamps)",
            xaxis_title=_AXIS_TITLE,
            yaxis_title="Table",
        )
        return fig

    prepared = prepared.sort_values(
        ["bar_start", "y_label"], kind="mergesort"
    ).reset_index(drop=True)
    y_order_top_first = prepared["y_label"].tolist()
    # Plotly categorical y puts the first categoryarray entry at the bottom.
    category_array = list(reversed(y_order_top_first))
    color_column, legend_title = _color_encoding(color_by)

    timeline = px.timeline(
        prepared,
        x_start="bar_start",
        x_end="bar_end",
        y="y_label",
        color=color_column,
        hover_data={
            "y_label": False,
            "bar_start": False,
            "bar_end": False,
            "hop_label": True,
            "owner_label": True,
            "id_dag": True,
            "id_task": True,
            "run_gate": True,
            "day_label": True,
            "latest_ts_started": True,
            "latest_ts_ended": True,
            "duration": True,
            "median_start_tod": True,
            "median_end_tod": True,
            "median_duration": True,
        },
    )
    timeline.update_traces(width=_BAR_WIDTH)

    fig = go.Figure(timeline)
    _add_median_markers(fig, prepared)
    fig.update_yaxes(
        title="Table",
        categoryorder="array",
        categoryarray=category_array,
        automargin=True,
    )
    _add_idle_bands(fig, prepared, idle_min_gap)
    _apply_time_axis(fig, prepared)
    fig.update_layout(
        title="Latest successful run (UTC) with median start/end",
        legend_title=legend_title,
        height=_chart_height(len(prepared)),
        bargap=0.25,
        margin=dict(l=16, r=16, t=48, b=48),
    )
    return fig


def _prepare_rows(frame: pd.DataFrame) -> pd.DataFrame:
    if frame is None or frame.empty:
        return pd.DataFrame()

    records: list[dict[str, Any]] = []
    for record in frame.to_dict(orient="records"):
        started = _as_datetime(record.get("latest_ts_started"))
        ended = _as_datetime(record.get("latest_ts_ended"))
        if started is None or ended is None:
            continue
        if ended < started:
            continue
        median_start = _as_time(record.get("median_start_tod"))
        median_end = _as_time(record.get("median_end_tod"))
        records.append(
            {
                "y_label": _row_label(record),
                # Real timestamps, not a time of day: an upstream that ran late
                # the evening before must plot left of the target it fed.
                "bar_start": started,
                "bar_end": ended,
                "level": record.get("level"),
                "hop_label": _hop_label(record.get("level")),
                "run_gate": _run_gate(record),
                "id_dag": record.get("id_dag"),
                "dag_label": _dag_label(record.get("id_dag")),
                "owner_label": _dag_label(record.get("dag_owner", record.get("owner"))),
                "id_task": record.get("id_task"),
                "latest_ts_started": started,
                "latest_ts_ended": ended,
                "duration": _format_hover_duration(ended - started),
                "median_start_tod": record.get("median_start_tod"),
                "median_end_tod": record.get("median_end_tod"),
                "median_duration": (
                    None
                    if median_start is None or median_end is None
                    else _format_hover_duration(_tod_delta(median_start, median_end))
                ),
            }
        )
    if not records:
        return pd.DataFrame()

    # Day offsets are relative to the target run, so the anchor has to be known
    # before any row can be labelled.
    anchor_day = _anchor_day(records)
    for record in records:
        bar_start = record["bar_start"]
        bar_end = record["bar_end"]
        record["anchor_day"] = anchor_day
        record["day_label"] = _day_label(bar_start.date(), anchor_day)
        for prefix in ("median_start", "median_end"):
            placed = _place_median(
                _as_time(record[f"{prefix}_tod"]), bar_start, bar_end
            )
            record[f"{prefix}_at"] = placed
            record[f"{prefix}_day"] = (
                None if placed is None else _day_label(placed.date(), anchor_day)
            )

    prepared = pd.DataFrame.from_records(records)
    prepared["y_label"] = _disambiguate_labels(prepared)
    return prepared


def _anchor_day(records: list[dict[str, Any]]) -> date:
    """Day 0: the target run's day, falling back to the newest run's day."""
    for record in records:
        level = record["level"]
        if _is_missing(level):
            continue
        try:
            if int(level) == 0:
                return record["bar_start"].date()
        except (TypeError, ValueError):
            continue
    return max(record["bar_start"] for record in records).date()


def _day_label(day: date, anchor_day: date) -> str:
    offset = (day - anchor_day).days
    return "D0" if offset == 0 else f"D{offset:+d}"


def _row_label(record: dict[str, Any]) -> str:
    table = record.get("table_name")
    if not _is_missing(table) and str(table).strip() not in ("", "nan", "None"):
        return str(table).strip()
    dag = record.get("id_dag")
    task = record.get("id_task")
    dag_s = "" if _is_missing(dag) else str(dag)
    task_s = "" if _is_missing(task) else str(task)
    return f"{dag_s} / {task_s}".strip(" /") or "(unknown)"


def _disambiguate_labels(prepared: pd.DataFrame) -> pd.Series:
    counts = prepared["y_label"].value_counts()
    duplicated = set(counts[counts > 1].index)
    labels: list[str] = []
    for record in prepared.to_dict(orient="records"):
        label = record["y_label"]
        if label in duplicated:
            task = record.get("id_task")
            task_s = "" if _is_missing(task) else str(task)
            labels.append(f"{label} ({task_s})" if task_s else label)
        else:
            labels.append(label)
    return pd.Series(labels, index=prepared.index)


def _hop_label(level: Any) -> str:
    if _is_missing(level):
        return "Hop ?"
    try:
        return f"Hop {int(level)}"
    except (TypeError, ValueError):
        return f"Hop {level}"


def _color_encoding(color_by: Literal["owner", "hop", "dag"]) -> tuple[str, str]:
    if color_by == "dag":
        return "dag_label", "DAG"
    if color_by == "hop":
        return "hop_label", "Hop"
    return "owner_label", "Owner"


def _dag_label(dag: Any) -> str:
    if _is_missing(dag):
        return "?"
    text = str(dag).strip()
    return "?" if text in ("", "nan", "None") else text


def _run_gate(record: dict[str, Any]) -> str:
    """Which run of this task the pick was drawn from."""
    level = record.get("level")
    if not _is_missing(level):
        try:
            if int(level) == 0:
                return "target run"
        except (TypeError, ValueError):
            pass
    if _is_missing(record.get("first_run_of_day")):
        return "run before seed"
    if record["first_run_of_day"]:
        return "first run of day, before seed"
    return "latest run before seed"


def _place_median(
    tod: time | None,
    bar_start: datetime,
    bar_end: datetime,
) -> datetime | None:
    """Project a time of day onto the calendar day nearest its own bar."""
    if tod is None:
        return None
    base = datetime.combine(bar_start.date(), tod)
    return min(
        (base + timedelta(days=shift) for shift in _DAY_SHIFTS),
        key=lambda point: _closer_to_bar(point, bar_start, bar_end),
    )


def _closer_to_bar(point: datetime, start: datetime, end: datetime) -> float:
    if start <= point <= end:
        return 0.0
    if point < start:
        return (start - point).total_seconds()
    return (point - end).total_seconds()


def _add_median_markers(fig: go.Figure, prepared: pd.DataFrame) -> None:
    _add_median_trace(fig, prepared, "median_start", "Median start", "#555555")
    _add_median_trace(fig, prepared, "median_end", "Median end", "#555555")


def _add_median_trace(
    fig: go.Figure,
    prepared: pd.DataFrame,
    prefix: str,
    name: str,
    color: str,
) -> None:
    points = prepared.dropna(subset=[f"{prefix}_at"])
    if points.empty:
        return
    placed = points[f"{prefix}_at"]
    # A marker is sized in pixels and ignores the category bandwidth, so the
    # tick is a zero-length bar: bar width is a fraction of the row, so it keeps
    # 70% of the task bar's height at every zoom level. Numeric y is not an
    # option here — on a category axis Plotly appends it as a new category.
    fig.add_trace(
        go.Bar(
            x=[0] * len(placed),
            base=placed,
            y=points["y_label"],
            orientation="h",
            width=_BAR_WIDTH * _MEDIAN_HEIGHT_RATIO,
            name=name,
            legendgroup=prefix,
            marker={"color": color, "line": {"width": 2, "color": color}},
            hoverinfo="skip",
        )
    )
    # A zero-length bar has no area to hover, so the tooltip rides an invisible
    # marker on the same point. Same legendgroup, so one legend click hides both.
    fig.add_trace(
        go.Scatter(
            x=placed,
            y=points["y_label"],
            mode="markers",
            name=name,
            legendgroup=prefix,
            showlegend=False,
            marker={"size": _MEDIAN_HOVER_SIZE, "opacity": 0, "color": color},
            # The median is a time of day with no date of its own, so the day it
            # is drawn on is only meaningful as an offset from the target.
            customdata=points[f"{prefix}_day"],
            hovertemplate=(f"{name}: %{{x|%H:%M:%S}} (%{{customdata}})<extra></extra>"),
        )
    )


def _apply_time_axis(fig: go.Figure, prepared: pd.DataFrame) -> None:
    axis_min, axis_max = _plot_span(prepared)
    span = axis_max - axis_min
    fig.update_xaxes(title=_AXIS_TITLE)
    if span <= _HOURLY_TICK_SPAN:
        fig.update_xaxes(tickformat="%H:%M", dtick=3_600_000)
    if span > _MIDNIGHT_LINE_SPAN:
        return
    anchor_day = prepared["anchor_day"].iloc[0]
    for midnight in _midnights_between(axis_min, axis_max):
        fig.add_vline(
            x=midnight.isoformat(),
            line_width=1,
            line_dash="dash",
            line_color="#888888",
            annotation_text=_day_label(midnight.date(), anchor_day),
            annotation_position="top",
        )


def _idle_windows(
    prepared: pd.DataFrame,
    min_gap: timedelta,
) -> list[tuple[datetime, datetime]]:
    """Stretches inside the bar span where no plotted task is running."""
    spans = sorted(
        (
            (_as_datetime(start), _as_datetime(end))
            for start, end in zip(
                prepared["bar_start"], prepared["bar_end"], strict=True
            )
        ),
        key=lambda span: span[0],
    )
    if not spans:
        return []
    windows: list[tuple[datetime, datetime]] = []
    covered_to = spans[0][1]
    for start, end in spans[1:]:
        if start - covered_to >= min_gap:
            windows.append((covered_to, start))
        # Coverage is the running union of every bar seen so far: a bar nested
        # inside a longer one must not open a gap the longer bar still fills.
        covered_to = max(covered_to, end)
    return windows


def _add_idle_bands(
    fig: go.Figure,
    prepared: pd.DataFrame,
    min_gap: timedelta,
) -> None:
    windows = _idle_windows(prepared, min_gap)
    if not windows:
        return
    for start, end in windows:
        fig.add_vrect(
            x0=start.isoformat(),
            x1=end.isoformat(),
            fillcolor=_IDLE_COLOR,
            opacity=_IDLE_OPACITY,
            line_width=0,
            layer="below",
            annotation_text=_format_duration(end - start),
            annotation_position="top left",
            annotation_font_size=10,
        )
    # A vrect is a shape, so it carries no legend entry and no hover of its own.
    fig.add_trace(
        go.Scatter(
            x=[None],
            y=[prepared["y_label"].iloc[0]],
            mode="markers",
            name=_IDLE_LEGEND_NAME,
            marker={
                "symbol": "square",
                "size": 12,
                "color": _IDLE_COLOR,
            },
            hoverinfo="skip",
            showlegend=True,
        )
    )


def _format_duration(delta: timedelta) -> str:
    total_minutes = int(delta.total_seconds() // 60)
    hours, minutes = divmod(total_minutes, 60)
    if hours and minutes:
        return f"{hours}h{minutes:02d}m"
    if hours:
        return f"{hours}h"
    if minutes:
        return f"{minutes}m"
    return f"{int(delta.total_seconds())}s"


def _tod_delta(start: time, end: time) -> timedelta:
    start_at = datetime.combine(_EPOCH_DATE, start.replace(tzinfo=None))
    end_at = datetime.combine(_EPOCH_DATE, end.replace(tzinfo=None))
    if end_at < start_at:
        end_at += timedelta(days=1)
    return end_at - start_at


def _format_hover_duration(delta: timedelta) -> str:
    total = max(0, int(delta.total_seconds()))
    hours, remainder = divmod(total, 3600)
    minutes, seconds = divmod(remainder, 60)
    if hours:
        if minutes or seconds:
            if seconds:
                return f"{hours}h{minutes:02d}m{seconds:02d}s"
            return f"{hours}h{minutes:02d}m"
        return f"{hours}h"
    if minutes:
        if seconds:
            return f"{minutes}m{seconds:02d}s"
        return f"{minutes}m"
    return f"{seconds}s"


def _plot_span(prepared: pd.DataFrame) -> tuple[datetime, datetime]:
    points = [prepared["bar_start"].min(), prepared["bar_end"].max()]
    for column in ("median_start_at", "median_end_at"):
        placed = prepared[column].dropna()
        if not placed.empty:
            points.extend([placed.min(), placed.max()])
    stamps = [pd.Timestamp(point).to_pydatetime() for point in points]
    return min(stamps), max(stamps)


def _midnights_between(start: datetime, end: datetime) -> Iterator[datetime]:
    midnight = datetime.combine(start.date() + timedelta(days=1), time.min)
    while midnight <= end:
        yield midnight
        midnight += timedelta(days=1)


def _chart_height(row_count: int) -> int:
    return min(
        _CHART_HEIGHT_MAX,
        max(_CHART_HEIGHT_MIN, row_count * _ROW_HEIGHT_PX + _CHART_HEIGHT_PAD),
    )


def _as_datetime(value: Any) -> datetime | None:
    if _is_missing(value):
        return None
    if isinstance(value, datetime):
        return value.replace(tzinfo=None) if value.tzinfo else value
    if isinstance(value, pd.Timestamp):
        if pd.isna(value):
            return None
        return value.to_pydatetime().replace(tzinfo=None)
    parsed = pd.to_datetime(value, errors="coerce")
    if pd.isna(parsed):
        return None
    return parsed.to_pydatetime().replace(tzinfo=None)


def _as_time(value: Any) -> time | None:
    if _is_missing(value):
        return None
    if isinstance(value, time):
        return value.replace(tzinfo=None) if value.tzinfo else value
    if isinstance(value, timedelta):
        return (datetime.combine(_EPOCH_DATE, time.min) + value).time()
    if isinstance(value, datetime):
        return value.time()
    if isinstance(value, pd.Timestamp):
        if pd.isna(value):
            return None
        return value.to_pydatetime().time()
    text = str(value).strip()
    if not text:
        return None
    parsed = pd.to_datetime(text, errors="coerce")
    if not pd.isna(parsed):
        return parsed.to_pydatetime().time()
    try:
        parts = text.split(":")
        hour = int(parts[0])
        minute = int(parts[1]) if len(parts) > 1 else 0
        second_part = parts[2] if len(parts) > 2 else "0"
        second = int(float(second_part))
        micro = int(round((float(second_part) - second) * 1_000_000))
        return time(hour, minute, second, micro)
    except (TypeError, ValueError, IndexError):
        return None


def _is_missing(value: Any) -> bool:
    if value is None:
        return True
    try:
        return bool(pd.isna(value))
    except (TypeError, ValueError):
        return False
