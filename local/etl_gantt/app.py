"""Streamlit UI for upstream ETL task timelines via Trino."""

from __future__ import annotations

from datetime import date, timedelta
from pathlib import Path

import streamlit as st

from chart import build_gantt_figure
from lineage import (
    InventoryRow,
    build_job_graph,
    frame_without_excluded_layers,
    lookup_inventory_rows,
    upstream_job_hops,
)
from query import (
    LOOKUP_TABLE,
    LOOKUP_TASK,
    MAX_DATE_SPAN_DAYS,
    QueryError,
    build_inventory_sql,
    build_upstream_runtime_sql,
)
from trino_client import connect_for_queries, read_sql

OUTPUT_CSV = Path(__file__).resolve().parent / "output.csv"

if "sidebar_state" not in st.session_state:
    st.session_state.sidebar_state = "expanded"

st.set_page_config(
    page_title="ETL Gantt",
    layout="wide",
    initial_sidebar_state=st.session_state.sidebar_state,
)
st.title("ETL Gantt")
st.caption(
    "Latest successful run and median time-of-day for a table (or task) "
    "and its upstream Airflow jobs."
)


@st.cache_resource
def _session():
    return connect_for_queries()


@st.cache_data(show_spinner="Reading Airflow job dependencies…")
def _job_graph():
    return build_job_graph()


@st.cache_data(show_spinner="Reading DAG inventory…")
def _inventory() -> list[InventoryRow]:
    frame = read_sql(_session().connection, build_inventory_sql())
    rows: list[InventoryRow] = []
    for record in frame.to_dict(orient="records"):
        dag = record.get("id_dag")
        task = record.get("id_task")
        table = record.get("table_name")
        if dag is None or task is None or table is None:
            continue
        location = record.get("files_location")
        rows.append(
            InventoryRow(
                dag=str(dag),
                task=str(task),
                table=str(table),
                files_location="" if location is None else str(location),
            )
        )
    return rows


try:
    session = _session()
except Exception as exc:
    st.error(f"Could not connect to Trino: {exc}")
    st.stop()

with st.sidebar:
    st.subheader("Connection")
    st.text(f"User: {session.user}")
    st.text(f"Host: {session.host}")

    st.subheader("Display")
    idle_gap_minutes = int(
        st.number_input(
            "Idle gap threshold (minutes)",
            min_value=0,
            value=15,
            step=1,
            help=(
                "Shade every span where no plotted task was running and that "
                "lasts at least this long. 0 shades every gap."
            ),
        )
    )
    color_label = st.radio(
        "Color by",
        ("DAG owner", "Hop level", "DAG id"),
        horizontal=True,
        help="Recolors the current Gantt; does not re-run the query.",
    )
    color_by = {"DAG owner": "owner", "Hop level": "hop", "DAG id": "dag"}[color_label]
    exclude_raw = st.checkbox(
        "Exclude raw layer",
        value=False,
        help=(
            "Hide upstream jobs whose DAG declaration workflow.layer is raw. "
            "Hop 0 (the target) is always kept. Does not re-run the query."
        ),
    )
    exclude_clean = st.checkbox(
        "Exclude clean layer",
        value=False,
        help=(
            "Hide upstream jobs whose DAG declaration workflow.layer is clean. "
            "Hop 0 (the target) is always kept. Does not re-run the query."
        ),
    )
    excluded_layers = set()
    if exclude_raw:
        excluded_layers.add("raw")
    if exclude_clean:
        excluded_layers.add("clean")

today = date.today()
default_end = today - timedelta(days=1)
default_start = today - timedelta(days=30)

lookup_label = st.radio(
    "Lookup by",
    ("Table name (FQN)", "Task id"),
    horizontal=True,
)
lookup_mode = LOOKUP_TASK if lookup_label == "Task id" else LOOKUP_TABLE
placeholder = (
    "load-dw-rent-fact-contracts"
    if lookup_mode == LOOKUP_TASK
    else "dw_rent.fact_contracts"
)
lookup_value = st.text_input(
    lookup_label,
    value="",
    placeholder=placeholder,
)

col_start, col_end = st.columns(2)
with col_start:
    start = st.date_input(
        "Start date",
        value=default_start,
        help=f"Window is at most {MAX_DATE_SPAN_DAYS} days inclusive.",
    )
if not isinstance(start, date):
    st.error("Start date must be a single day.")
    st.stop()
max_end = start + timedelta(days=MAX_DATE_SPAN_DAYS - 1)
end_default = min(max(default_end, start), max_end)
with col_end:
    end = st.date_input(
        "End date",
        value=end_default,
        min_value=start,
        max_value=max_end,
        help=f"Window is at most {MAX_DATE_SPAN_DAYS} days inclusive.",
    )

restrict_hops = st.checkbox("Restrict hop depth", value=False)
max_hop_level = None
if restrict_hops:
    max_hop_level = int(
        st.number_input(
            "Max hop level",
            min_value=1,
            value=1,
            step=1,
            help=(
                "1 = direct upstreams only. Hop 0 (the target) is always kept. "
                "Only waits Airflow enforces count, so a cron-scheduled DAG has "
                "no cross-DAG upstreams."
            ),
        )
    )
show_before_d0 = st.checkbox(
    "Show dependencies before D0",
    value=False,
    help=(
        "Include upstream runs that finished before the target run's day. "
        "Hop 0 (the target) is always kept. Changing this requires Run query."
    ),
)


def _collapse_sidebar():
    st.session_state.sidebar_state = "collapsed"


run = st.button("Run query", type="primary", on_click=_collapse_sidebar)
show_table = st.toggle("Show table", value=False)

if "result_frame" not in st.session_state:
    st.session_state.result_frame = None
if "result_sql" not in st.session_state:
    st.session_state.result_sql = None
if "result_error" not in st.session_state:
    st.session_state.result_error = None


def _with_dag_owners(frame):
    graph = _job_graph()
    attached = frame.copy()
    attached["dag_owner"] = [
        graph.owners.get(str(dag), "?") if dag is not None else "?"
        for dag in attached["id_dag"]
    ]
    attached["layer"] = [
        graph.layers.get(str(dag), "") if dag is not None else ""
        for dag in attached["id_dag"]
    ]
    return attached


if run:
    st.session_state.result_frame = None
    st.session_state.result_sql = None
    st.session_state.result_error = None
    try:
        with st.spinner("Resolving job dependencies…"):
            inventory = _inventory()
            seed_rows = lookup_inventory_rows(lookup_mode, lookup_value, inventory)
            if not seed_rows:
                raise QueryError("No DAG inventory row for that lookup.")
            job_hops = upstream_job_hops(
                [row.table for row in seed_rows],
                inventory,
                _job_graph(),
                max_hop_level=max_hop_level,
            )
        sql = build_upstream_runtime_sql(
            start,
            end,
            seed_jobs=[(row.dag, row.task, row.table) for row in seed_rows],
            max_hop_level=max_hop_level,
            job_hops=job_hops,
            include_before_d0=show_before_d0,
        )
        st.session_state.result_sql = sql
    except QueryError as exc:
        st.session_state.result_error = str(exc)
    except Exception as exc:
        st.session_state.result_error = f"Could not resolve job dependencies: {exc}"
    else:
        try:
            with st.spinner("Running query…"):
                frame = read_sql(session.connection, sql)
            frame.to_csv(OUTPUT_CSV, index=False)
            st.session_state.result_frame = frame
        except Exception as exc:
            st.session_state.result_error = str(exc)

if st.session_state.result_error:
    st.error(st.session_state.result_error)

if st.session_state.result_sql:
    with st.expander("SQL", expanded=False):
        st.code(st.session_state.result_sql, language="sql")

frame = st.session_state.result_frame
if frame is not None:
    st.success(f"{len(frame)} row(s)")
    st.caption(f"Overwrote {OUTPUT_CSV}")
    if "level" in frame.columns and not (frame["level"] > 0).any():
        st.warning(
            "No upstream Airflow jobs found in inner_dependencies "
            "or dags/dependencies.yaml."
        )
    display = frame_without_excluded_layers(
        _with_dag_owners(frame),
        _job_graph().layers,
        excluded_layers,
    )
    st.plotly_chart(
        build_gantt_figure(
            display,
            idle_min_gap=timedelta(minutes=idle_gap_minutes),
            color_by=color_by,
        ),
        width="stretch",
    )
    if show_table:
        st.dataframe(display, width="stretch")
