from datetime import datetime, time, timedelta

import pandas as pd

from chart import build_gantt_figure


def _frame(**overrides):
    row = {
        "level": 0,
        "table_name": "dw_rent.fact_contracts",
        "id_dag": "dw_rent",
        "id_task": "load-dw-rent-fact-contracts",
        "dag_owner": "Data Rent",
        "latest_ts_started": datetime(2026, 8, 26, 10, 0, 0),
        "latest_ts_ended": datetime(2026, 8, 26, 11, 0, 0),
        "median_start_tod": time(10, 5, 0),
        "median_end_tod": time(10, 50, 0),
    }
    row.update(overrides)
    return pd.DataFrame([row])


_MEDIAN_NAMES = ("Median start", "Median end")


def _bar_traces(fig):
    """Task bars only: median ticks are bars too, but not runs."""
    return [
        trace
        for trace in fig.data
        if trace.type == "bar" and trace.name not in _MEDIAN_NAMES
    ]


def _scatter_by_name(fig, name):
    matches = [
        trace for trace in fig.data if trace.name == name and trace.type == "scatter"
    ]
    assert matches, f"missing trace {name!r}"
    return matches[0]


def _median_tick(fig, name):
    """The drawn tick: a zero-length bar, so its height follows the row."""
    matches = [
        trace for trace in fig.data if trace.name == name and trace.type == "bar"
    ]
    assert matches, f"missing median tick {name!r}"
    return matches[0]


def _bar_bounds(trace, index=0):
    start = pd.Timestamp(trace.base[index]).to_pydatetime()
    return start, start + pd.to_timedelta(trace.x[index], unit="ms")


def _bars_by_y(fig):
    bars = {}
    for trace in _bar_traces(fig):
        for index, label in enumerate(trace.y):
            bars[label] = {
                "start": _bar_bounds(trace, index)[0],
                "hover": list(trace.customdata[index]),
            }
    return bars


def _midnight_lines(fig):
    return [shape for shape in fig.layout.shapes if shape.line.dash == "dash"]


def _idle_bands(fig):
    return [
        (
            pd.Timestamp(shape.x0).to_pydatetime(),
            pd.Timestamp(shape.x1).to_pydatetime(),
        )
        for shape in fig.layout.shapes
        if shape.type == "rect"
    ]


def test_bar_keeps_its_real_date():
    fig = build_gantt_figure(_frame())
    bars = _bar_traces(fig)
    assert len(bars) == 1
    start, end = _bar_bounds(bars[0])
    assert start == datetime(2026, 8, 26, 10, 0, 0)
    assert end == datetime(2026, 8, 26, 11, 0, 0)
    assert list(bars[0].y) == ["dw_rent.fact_contracts"]


def test_run_spanning_midnight_keeps_both_real_dates():
    fig = build_gantt_figure(
        _frame(
            latest_ts_started=datetime(2026, 8, 26, 23, 0, 0),
            latest_ts_ended=datetime(2026, 8, 27, 1, 0, 0),
            median_start_tod=time(22, 50, 0),
            median_end_tod=time(0, 45, 0),
        )
    )
    start, end = _bar_bounds(_bar_traces(fig)[0])
    assert start == datetime(2026, 8, 26, 23, 0, 0)
    assert end == datetime(2026, 8, 27, 1, 0, 0)

    median_start = pd.Timestamp(
        _scatter_by_name(fig, "Median start").x[0]
    ).to_pydatetime()
    median_end = pd.Timestamp(_scatter_by_name(fig, "Median end").x[0]).to_pydatetime()
    # Each median lands on the calendar day that puts it next to its own bar.
    assert median_start == datetime(2026, 8, 26, 22, 50, 0)
    assert median_end == datetime(2026, 8, 27, 0, 45, 0)


def test_previous_day_upstream_plots_before_the_target():
    frame = pd.concat(
        [
            _frame(
                table_name="datalake_chatbot.sessions",
                level=0,
                latest_ts_started=datetime(2026, 8, 27, 5, 33, 0),
                latest_ts_ended=datetime(2026, 8, 27, 5, 41, 0),
            ),
            _frame(
                table_name="datalake_copilot_service_clean.session",
                level=1,
                latest_ts_started=datetime(2026, 8, 26, 23, 56, 19),
                latest_ts_ended=datetime(2026, 8, 27, 0, 2, 0),
            ),
        ],
        ignore_index=True,
    )
    fig = build_gantt_figure(frame)
    starts = {label: bar["start"] for label, bar in _bars_by_y(fig).items()}
    assert (
        starts["datalake_copilot_service_clean.session"]
        < starts["datalake_chatbot.sessions"]
    )
    # First entry of categoryarray is the bottom row, so the target ends up last.
    assert list(fig.layout.yaxis.categoryarray) == [
        "datalake_chatbot.sessions",
        "datalake_copilot_service_clean.session",
    ]


def test_day_labels_are_offsets_from_the_target_day():
    frame = pd.concat(
        [
            _frame(
                table_name="datalake_chatbot.sessions",
                level=0,
                latest_ts_started=datetime(2026, 8, 27, 5, 33, 0),
                latest_ts_ended=datetime(2026, 8, 27, 5, 41, 0),
                median_start_tod=time(5, 30, 0),
                median_end_tod=time(5, 40, 0),
            ),
            _frame(
                table_name="datalake_copilot_service_clean.session",
                level=1,
                latest_ts_started=datetime(2026, 8, 26, 23, 56, 19),
                latest_ts_ended=datetime(2026, 8, 27, 0, 2, 0),
                median_start_tod=time(23, 50, 0),
                median_end_tod=time(0, 5, 0),
            ),
        ],
        ignore_index=True,
    )
    fig = build_gantt_figure(frame)
    hover = {label: bar["hover"] for label, bar in _bars_by_y(fig).items()}
    assert "D0" in hover["datalake_chatbot.sessions"]
    assert "D-1" in hover["datalake_copilot_service_clean.session"]

    medians = dict(
        zip(
            _scatter_by_name(fig, "Median start").y,
            _scatter_by_name(fig, "Median start").customdata,
            strict=True,
        )
    )
    assert medians["datalake_chatbot.sessions"] == "D0"
    assert medians["datalake_copilot_service_clean.session"] == "D-1"


def test_axis_is_labelled_utc_with_hourly_ticks_on_a_short_span():
    fig = build_gantt_figure(_frame())
    assert fig.layout.xaxis.title.text == "Run time (UTC)"
    assert fig.layout.xaxis.tickformat == "%H:%M"
    assert fig.layout.xaxis.dtick == 3_600_000


def test_midnight_is_marked_with_its_day_offset():
    fig = build_gantt_figure(
        _frame(
            level=0,
            latest_ts_started=datetime(2026, 8, 26, 23, 0, 0),
            latest_ts_ended=datetime(2026, 8, 27, 1, 0, 0),
        )
    )
    assert len(_midnight_lines(fig)) == 1
    assert [note.text for note in fig.layout.annotations] == ["D+1"]


def test_wide_span_drops_the_hourly_grid():
    frame = pd.concat(
        [
            _frame(level=0),
            _frame(
                table_name="dw_rent.fact_stale",
                level=1,
                latest_ts_started=datetime(2026, 8, 1, 10, 0, 0),
                latest_ts_ended=datetime(2026, 8, 1, 11, 0, 0),
            ),
        ],
        ignore_index=True,
    )
    fig = build_gantt_figure(frame)
    assert fig.layout.xaxis.dtick is None
    assert _midnight_lines(fig) == []


def test_missing_timestamps_are_dropped():
    frame = pd.concat(
        [
            _frame(),
            _frame(
                table_name="dw_rent.fact_missing",
                latest_ts_started=pd.NaT,
                latest_ts_ended=pd.NaT,
            ),
        ],
        ignore_index=True,
    )
    fig = build_gantt_figure(frame)
    bars = _bar_traces(fig)
    labels = [label for trace in bars for label in trace.y]
    assert labels == ["dw_rent.fact_contracts"]


def test_hover_names_the_run_gate_per_hop():
    frame = pd.concat(
        [
            _frame(),
            _frame(
                table_name="datalake_ebdb_clean.partner_agent",
                level=3,
                first_run_of_day=True,
            ),
            _frame(
                table_name="datalake_langfuse_clean.traces",
                level=1,
                first_run_of_day=False,
            ),
        ],
        ignore_index=True,
    )
    gates = [
        cell
        for trace in _bar_traces(build_gantt_figure(frame))
        for row in trace.customdata
        for cell in row
    ]
    assert "target run" in gates
    assert "first run of day, before seed" in gates
    assert "latest run before seed" in gates


def _hover_cells(fig):
    return [
        cell for trace in _bar_traces(fig) for row in trace.customdata for cell in row
    ]


def test_hover_includes_latest_and_median_duration():
    cells = _hover_cells(build_gantt_figure(_frame()))
    assert "1h" in cells
    assert "45m" in cells


def test_hover_median_duration_wraps_midnight():
    cells = _hover_cells(
        build_gantt_figure(
            _frame(
                latest_ts_started=datetime(2026, 8, 26, 23, 0, 0),
                latest_ts_ended=datetime(2026, 8, 27, 1, 0, 0),
                median_start_tod=time(22, 50, 0),
                median_end_tod=time(0, 45, 0),
            )
        )
    )
    assert "2h" in cells
    assert "1h55m" in cells


def _two_bars(second_start, second_end, **overrides):
    return pd.concat(
        [
            _frame(level=0),
            _frame(
                table_name="datalake_internal_chat_clean.internal_chat_messages",
                level=1,
                latest_ts_started=second_start,
                latest_ts_ended=second_end,
                **overrides,
            ),
        ],
        ignore_index=True,
    )


def test_gap_between_runs_is_shaded():
    fig = build_gantt_figure(
        _two_bars(datetime(2026, 8, 26, 14, 30, 0), datetime(2026, 8, 26, 15, 0, 0))
    )
    assert _idle_bands(fig) == [
        (datetime(2026, 8, 26, 11, 0, 0), datetime(2026, 8, 26, 14, 30, 0))
    ]


def test_back_to_back_runs_leave_no_gap():
    fig = build_gantt_figure(
        _two_bars(datetime(2026, 8, 26, 11, 0, 0), datetime(2026, 8, 26, 12, 0, 0))
    )
    assert _idle_bands(fig) == []


def test_overlapping_runs_leave_no_gap():
    fig = build_gantt_figure(
        _two_bars(datetime(2026, 8, 26, 10, 30, 0), datetime(2026, 8, 26, 12, 0, 0))
    )
    assert _idle_bands(fig) == []


def test_run_nested_in_a_longer_run_leaves_no_gap():
    frame = pd.concat(
        [
            _frame(
                level=0,
                latest_ts_started=datetime(2026, 8, 26, 10, 0, 0),
                latest_ts_ended=datetime(2026, 8, 26, 16, 0, 0),
            ),
            _frame(
                table_name="dw_rent.fact_nested",
                level=1,
                latest_ts_started=datetime(2026, 8, 26, 10, 30, 0),
                latest_ts_ended=datetime(2026, 8, 26, 11, 0, 0),
            ),
            _frame(
                table_name="dw_rent.fact_after",
                level=1,
                latest_ts_started=datetime(2026, 8, 26, 15, 0, 0),
                latest_ts_ended=datetime(2026, 8, 26, 15, 30, 0),
            ),
        ],
        ignore_index=True,
    )
    # The nested bar ends at 11:00, but the level-0 bar still covers 11:00-15:00.
    assert _idle_bands(build_gantt_figure(frame)) == []


def test_gap_under_the_threshold_is_not_shaded():
    frame = _two_bars(datetime(2026, 8, 26, 11, 2, 0), datetime(2026, 8, 26, 11, 30, 0))
    assert _idle_bands(build_gantt_figure(frame)) == []
    assert _idle_bands(
        build_gantt_figure(frame, idle_min_gap=timedelta(minutes=1))
    ) == [(datetime(2026, 8, 26, 11, 0, 0), datetime(2026, 8, 26, 11, 2, 0))]


def test_idle_legend_entry_appears_only_with_a_band():
    with_gap = build_gantt_figure(
        _two_bars(datetime(2026, 8, 26, 14, 30, 0), datetime(2026, 8, 26, 15, 0, 0))
    )
    without_gap = build_gantt_figure(
        _two_bars(datetime(2026, 8, 26, 11, 0, 0), datetime(2026, 8, 26, 12, 0, 0))
    )
    assert "No dependency running" in [trace.name for trace in with_gap.data]
    assert "No dependency running" not in [trace.name for trace in without_gap.data]


def test_idle_band_is_annotated_with_its_duration():
    fig = build_gantt_figure(
        _two_bars(datetime(2026, 8, 26, 14, 30, 0), datetime(2026, 8, 26, 15, 0, 0))
    )
    assert "3h30m" in [note.text for note in fig.layout.annotations]


def test_color_by_hop_groups_bars_by_hop():
    frame = pd.concat(
        [
            _frame(level=0),
            _frame(
                table_name="dw_rent.fact_stale",
                level=1,
                latest_ts_started=datetime(2026, 8, 26, 8, 0, 0),
                latest_ts_ended=datetime(2026, 8, 26, 9, 0, 0),
            ),
        ],
        ignore_index=True,
    )
    fig = build_gantt_figure(frame, color_by="hop")
    assert {trace.name for trace in _bar_traces(fig)} == {"Hop 0", "Hop 1"}
    assert fig.layout.legend.title.text == "Hop"


def test_default_color_groups_bars_by_owner():
    frame = pd.concat(
        [
            _frame(level=0),
            _frame(
                table_name="datalake_chatbot.sessions",
                id_dag="datalake_chatbot",
                dag_owner="Data Conversational XP",
                id_task="load-datalake-chatbot-sessions",
                level=1,
                latest_ts_started=datetime(2026, 8, 26, 8, 0, 0),
                latest_ts_ended=datetime(2026, 8, 26, 9, 0, 0),
            ),
        ],
        ignore_index=True,
    )
    fig = build_gantt_figure(frame)
    assert {trace.name for trace in _bar_traces(fig)} == {
        "Data Rent",
        "Data Conversational XP",
    }
    assert fig.layout.legend.title.text == "Owner"


def test_missing_owner_is_grouped_as_unknown():
    fig = build_gantt_figure(_frame(dag_owner=None))
    assert {trace.name for trace in _bar_traces(fig)} == {"?"}
    assert fig.layout.legend.title.text == "Owner"


def test_color_by_dag_groups_bars_by_dag():
    frame = pd.concat(
        [
            _frame(level=0),
            _frame(
                table_name="datalake_chatbot.sessions",
                id_dag="datalake_chatbot",
                id_task="load-datalake-chatbot-sessions",
                level=1,
                latest_ts_started=datetime(2026, 8, 26, 8, 0, 0),
                latest_ts_ended=datetime(2026, 8, 26, 9, 0, 0),
            ),
        ],
        ignore_index=True,
    )
    fig = build_gantt_figure(frame, color_by="dag")
    assert {trace.name for trace in _bar_traces(fig)} == {
        "dw_rent",
        "datalake_chatbot",
    }
    assert fig.layout.legend.title.text == "DAG"


def test_median_traces_are_present():
    fig = build_gantt_figure(_frame())
    names = [trace.name for trace in fig.data]
    assert "Median start" in names
    assert "Median end" in names
    start = _scatter_by_name(fig, "Median start")
    end = _scatter_by_name(fig, "Median end")
    assert start.mode == "markers"
    assert end.mode == "markers"
    # Hover rides an invisible marker; the tick itself is the bar.
    assert start.marker.opacity == 0
    assert end.marker.opacity == 0


def test_median_tick_is_70_percent_of_the_bar_height():
    fig = build_gantt_figure(_frame())
    bar_width = _bar_traces(fig)[0].width
    for name in ("Median start", "Median end"):
        tick = _median_tick(fig, name)
        assert tick.width == bar_width * 0.7
        # Zero length in time, so the tick stays a hairline at any x zoom.
        assert list(tick.x) == [0]


def test_median_tick_sits_on_the_same_row_as_its_bar():
    fig = build_gantt_figure(_frame())
    tick = _median_tick(fig, "Median start")
    assert list(tick.y) == ["dw_rent.fact_contracts"]
    assert pd.Timestamp(tick.base[0]).to_pydatetime() == datetime(2026, 8, 26, 10, 5)
    # A row label, not a category index: numeric y becomes a new category.
    assert list(fig.layout.yaxis.categoryarray) == ["dw_rent.fact_contracts"]


def test_median_legend_entry_toggles_tick_and_hover_together():
    fig = build_gantt_figure(_frame())
    for prefix, name in (
        ("median_start", "Median start"),
        ("median_end", "Median end"),
    ):
        tick = _median_tick(fig, name)
        hover = _scatter_by_name(fig, name)
        assert tick.legendgroup == hover.legendgroup == prefix
        assert tick.showlegend is not False
        assert hover.showlegend is False
