"""Streamlit UI for on-demand EMR cluster metrics."""

from __future__ import annotations

import re
import time
from datetime import datetime, timezone

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import streamlit as st
from aws import (
    available_environments,
    clear_credential_cache,
    default_region,
    ec2_role_arn,
    emr_role_arn,
    logs_base_uri,
    normalize_environment,
    validate_roles,
)
from logs import ClusterLogsResult
from metrics import EMR_PERIOD_SEC, TIME_RANGE_HOURS, load_all_metrics
from pricing import (
    load_static_prices,
    pricing_refresh_status,
    start_refresh_static_prices,
)
from streamlit_autorefresh import st_autorefresh

st.set_page_config(page_title="EMR Monitor", layout="wide")
st.title("EMR Local Metrics Monitor")

CLUSTER_ID_PATTERN = r"^j-[A-Z0-9]+$"
# Bump when cached payload shape changes (e.g. ClusterLogsResult fields).
_LOAD_CACHE_VERSION = 17
_PRICING_SPINNER_FRAMES = ("⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏")


def _filter_metrics(df: pd.DataFrame, names: list[str]) -> pd.DataFrame:
    if df.empty:
        return df
    return df[df["metric_name"].isin(names)].copy()


def _mib_to_gb(df: pd.DataFrame) -> pd.DataFrame:
    """Convert EMR YARN memory values (MiB reported as MB) to GB for display."""
    if df.empty:
        return df
    out = df.copy()
    out["value"] = out["value"] / 1024
    out["metric_name"] = out["metric_name"].str.replace("MB", " GB", regex=False)
    return out


def _bytes_to_gb(df: pd.DataFrame) -> pd.DataFrame:
    """Convert CloudWatch Agent memory byte counters to GB for display."""
    if df.empty:
        return df
    out = df.copy()
    out["value"] = out["value"] / (1024**3)
    return out


def _line_chart(
    df: pd.DataFrame,
    *,
    title: str,
    color: str | None = None,
    y_title: str = "Value",
) -> go.Figure | None:
    if df.empty:
        return None
    if color:
        fig = px.line(
            df,
            x="timestamp",
            y="value",
            color=color,
            title=title,
            labels={"timestamp": "Time (UTC)", "value": y_title},
        )
    else:
        fig = px.line(
            df,
            x="timestamp",
            y="value",
            color="metric_name",
            title=title,
            labels={"timestamp": "Time (UTC)", "value": y_title},
        )
    fig.update_layout(hovermode="x unified", legend=dict(orientation="h", y=-0.2))
    fig.update_yaxes(rangemode="tozero")
    return fig


def _instance_label(row: pd.Series) -> str:
    node_name = row.get("node_name")
    iid = row.get("instance_id") or "?"
    itype = row.get("instance_type")
    if node_name:
        if itype:
            return f"{node_name} ({iid}, {itype})"
        return f"{node_name} ({iid})"
    role = (row.get("role") or "?").upper()
    if role == "MASTER":
        return f"Master ({iid})"
    if role == "CORE":
        return f"core ({iid})"
    if role == "TASK":
        return f"task ({iid})"
    return f"{role} ({iid})"


def _volume_label(row: pd.Series) -> str:
    node_name = row.get("node_name") or "?"
    iid = row.get("instance_id") or "?"
    vid = row.get("volume_id") or ""
    if not vid:
        return f"{node_name} ({iid}) · all volumes"
    return f"{node_name} ({iid}) · {vid}"


def _ec2_chart(
    df: pd.DataFrame,
    metric_name: str,
    title: str,
    *,
    y_title: str = "Value",
    to_gb: bool = False,
) -> go.Figure | None:
    subset = df[df["metric_name"] == metric_name].copy()
    if subset.empty:
        return None
    if to_gb:
        subset = _bytes_to_gb(subset)
        y_title = "GB"
    subset["series"] = subset.apply(_instance_label, axis=1)
    return _line_chart(subset, title=title, color="series", y_title=y_title)


def _ebs_throughput_mib_per_sec(df: pd.DataFrame) -> pd.DataFrame:
    """Convert EBS Volume*Bytes Sum counters to MiB/s over the fetch period."""
    if df.empty:
        return df
    out = df.copy()
    out["value"] = out["value"] / EMR_PERIOD_SEC / (1024 * 1024)
    return out


def _ebs_idle_percent(df: pd.DataFrame) -> pd.DataFrame:
    """Convert EBS VolumeIdleTime Sum (seconds) to idle % of the fetch period."""
    if df.empty:
        return df
    out = df.copy()
    out["value"] = out["value"] / EMR_PERIOD_SEC * 100
    return out


def _ebs_chart(
    df: pd.DataFrame,
    metric_name: str,
    title: str,
    *,
    y_title: str = "Value",
    transform=None,
) -> go.Figure | None:
    subset = df[df["metric_name"] == metric_name].copy()
    if subset.empty:
        return None
    if transform is not None:
        subset = transform(subset)
    subset["series"] = subset.apply(_volume_label, axis=1)
    return _line_chart(subset, title=title, color="series", y_title=y_title)


def _plot_combined_traces(
    figs: list[tuple[go.Figure | None, str]],
    *,
    title: str,
    y_title: str,
) -> go.Figure | None:
    combined = go.Figure()
    added = False
    for fig, suffix in figs:
        if not fig:
            continue
        for trace in fig.data:
            trace.name = f"{trace.name} ({suffix})"
            combined.add_trace(trace)
            added = True
    if not added:
        return None
    combined.update_layout(
        title=title,
        xaxis_title="Time (UTC)",
        yaxis_title=y_title,
        yaxis=dict(rangemode="tozero"),
        hovermode="x unified",
        legend=dict(orientation="h", y=-0.3),
    )
    return combined


def _format_usd(amount: float) -> str:
    return f"${amount:,.2f}"


def _format_hours(hours: float) -> str:
    total_minutes = int(round(hours * 60))
    whole_hours, minutes = divmod(total_minutes, 60)
    if whole_hours and minutes:
        return f"{whole_hours}h {minutes}m"
    if whole_hours:
        return f"{whole_hours}h"
    if minutes:
        return f"{minutes}m"
    return "0m"


def render_cluster_cost(cost_estimate) -> None:
    if cost_estimate is None:
        return

    st.subheader("Estimated cost")
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Total", _format_usd(cost_estimate.total_usd))
    c2.metric("EC2 compute", _format_usd(cost_estimate.total_compute_usd))
    c3.metric("EBS storage", _format_usd(cost_estimate.total_ebs_usd))
    c4.metric("Cluster runtime", _format_hours(cost_estimate.cluster_hours))

    updated = cost_estimate.prices_updated_at or "unknown"
    st.info(
        "Estimated cost from `static_prices.json` (Linux on-demand EC2 + EBS "
        f"for `{cost_estimate.pricing_region}`, last updated {updated}). "
        "Does not include EMR fees, data transfer, or spot/discount pricing."
    )

    if cost_estimate.missing_instance_types:
        st.warning(
            "No on-demand EC2 price found for: "
            + ", ".join(f"`{itype}`" for itype in cost_estimate.missing_instance_types)
        )

    if not cost_estimate.instance_lines and not cost_estimate.ebs_lines:
        return

    with st.expander("Cost details", expanded=False):
        if cost_estimate.instance_lines:
            st.caption("EC2 compute (Linux on-demand)")
            st.dataframe(
                pd.DataFrame(
                    [
                        {
                            "node": line.node_name,
                            "instance_id": line.instance_id,
                            "instance_type": line.instance_type,
                            "hours": round(line.hours, 2),
                            "rate_usd_h": line.hourly_usd,
                            "cost_usd": round(line.compute_cost_usd, 4),
                        }
                        for line in cost_estimate.instance_lines
                    ]
                ),
                width="stretch",
                hide_index=True,
            )

        if cost_estimate.ebs_lines:
            st.caption("EBS storage")
            st.dataframe(
                pd.DataFrame(
                    [
                        {
                            "node": line.node_name,
                            "volume_id": line.volume_id or "(aggregate)",
                            "type": line.volume_type,
                            "size_gb": line.size_gb,
                            "hours": round(line.hours, 2),
                            "rate_usd_gb_month": line.gb_month_usd,
                            "cost_usd": round(line.storage_cost_usd, 4),
                        }
                        for line in cost_estimate.ebs_lines
                    ]
                ),
                width="stretch",
                hide_index=True,
            )


def _render_cluster_status_row(items: list[tuple[str, str]]) -> None:
    cells = "".join(
        (
            '<div class="emr-status-cell">'
            f'<div class="emr-status-label">{label}</div>'
            f'<div class="emr-status-value">{value}</div>'
            "</div>"
        )
        for label, value in items
    )
    st.markdown(
        f"""
        <style>
        .emr-status-row {{
            display: grid;
            grid-template-columns: repeat({len(items)}, minmax(0, 1fr));
            gap: 0.5rem 0.75rem;
            margin-bottom: 0.25rem;
        }}
        .emr-status-label {{
            font-size: 0.78rem;
            color: rgb(128, 128, 128);
            margin-bottom: 0.1rem;
        }}
        .emr-status-value {{
            font-size: 0.92rem;
            font-weight: 600;
            line-height: 1.25;
            word-break: break-word;
        }}
        </style>
        <div class="emr-status-row">{cells}</div>
        """,
        unsafe_allow_html=True,
    )


def render_cluster_header(info) -> None:
    task_instances = [inst for inst in info.instances if inst.role == "TASK"]
    task_count = len(task_instances)
    task_types = sorted({inst.instance_type for inst in task_instances if inst.instance_type})
    task_type_label = task_types[0] if len(task_types) == 1 else (
        ", ".join(task_types) if task_types else "—"
    )

    _render_cluster_status_row(
        [
            ("State", info.state),
            ("Master", info.master_instance_type or "—"),
            ("Core nodes", str(info.core_instance_count)),
            ("Core type", info.core_instance_type or "—"),
            ("Task nodes", str(task_count)),
            ("Task type", task_type_label),
        ]
    )

    st.caption(
        f"**{info.name}** · {info.release_label} · "
        f"{len(info.instances)} EC2 instance(s)"
    )
    if info.status_message:
        st.info(info.status_message)


def _format_step_duration(
    started_at: datetime | None, ended_at: datetime | None
) -> str:
    if started_at is None:
        return "—"
    end = ended_at or datetime.now(timezone.utc)
    delta = end - started_at.astimezone(timezone.utc)
    if delta.total_seconds() < 0:
        return "—"
    total = int(delta.total_seconds())
    hours, rem = divmod(total, 3600)
    minutes, seconds = divmod(rem, 60)
    if hours:
        return f"{hours}h {minutes}m"
    if minutes:
        return f"{minutes}m {seconds}s"
    return f"{seconds}s"


def render_steps(info) -> None:
    if not info.steps:
        return
    st.subheader("Steps")
    steps_df = pd.DataFrame(
        [
            {
                "step_id": s.step_id,
                "name": s.name,
                "state": s.state,
                "duration": _format_step_duration(s.started_at, s.ended_at),
            }
            for s in info.steps
        ]
    )
    st.dataframe(steps_df, width='stretch', hide_index=True)


def render_emr_charts(emr_df: pd.DataFrame) -> None:
    st.subheader("Cluster metrics (YARN)")

    row1_a, row1_b = st.columns(2)
    memory_metrics = [
        "MemoryTotalMB",
        "MemoryAllocatedMB",
        "MemoryAvailableMB",
    ]
    mem_df = _mib_to_gb(_filter_metrics(emr_df, memory_metrics))
    fig_mem = _line_chart(mem_df, title="YARN memory (GB)", y_title="GB")
    if fig_mem:
        row1_a.plotly_chart(fig_mem, width='stretch')
    else:
        row1_a.caption("No YARN memory data in this window.")

    pct_df = _filter_metrics(emr_df, ["YARNMemoryAvailablePercentage"])
    fig_pct = _line_chart(pct_df, title="YARN memory available (%)")
    if fig_pct:
        row1_b.plotly_chart(fig_pct, width='stretch')
    else:
        row1_b.caption("No YARN memory % data in this window.")

    row2_a, row2_b, row2_c = st.columns(3)
    container_df = _filter_metrics(
        emr_df, ["ContainerAllocated", "ContainerPending"]
    )
    fig_cont = _line_chart(container_df, title="YARN containers")
    if fig_cont:
        row2_a.plotly_chart(fig_cont, width='stretch')
    else:
        row2_a.caption("No YARN container data in this window.")

    apps_df = _filter_metrics(
        emr_df, ["AppsRunning", "AppsPending", "AppsCompleted"]
    )
    fig_apps = _line_chart(apps_df, title="YARN applications")
    if fig_apps:
        row2_b.plotly_chart(fig_apps, width='stretch')
    else:
        row2_b.caption("No YARN application data in this window.")

    unhealthy_df = _filter_metrics(emr_df, ["MRUnhealthyNodes"])
    fig_unhealthy = _line_chart(
        unhealthy_df,
        title="Unhealthy YARN nodes (MRUnhealthyNodes)",
        y_title="Nodes",
    )
    if fig_unhealthy:
        row2_c.plotly_chart(fig_unhealthy, width='stretch')
    else:
        row2_c.caption("No MRUnhealthyNodes data in this window.")


def render_ec2_charts(ec2_df: pd.DataFrame) -> None:
    st.subheader("Per-node EC2 metrics")

    row1_a, row1_b = st.columns(2)
    fig_cpu = _ec2_chart(ec2_df, "CPUUtilization", "CPU utilization (%)")
    if fig_cpu:
        row1_a.plotly_chart(fig_cpu, width='stretch')
    else:
        row1_a.caption("No CPU data in this window.")

    fig_net = _plot_combined_traces(
        [
            (_ec2_chart(ec2_df, "NetworkIn", "Network in (bytes)"), "in"),
            (_ec2_chart(ec2_df, "NetworkOut", "Network out (bytes)"), "out"),
        ],
        title="Network in / out",
        y_title="Bytes",
    )
    if fig_net:
        row1_b.plotly_chart(fig_net, width='stretch')
    else:
        row1_b.caption("No network data in this window.")

    fig_health = _ec2_chart(ec2_df, "StatusCheckFailed", "Status check failed")
    if fig_health:
        st.plotly_chart(fig_health, width='stretch')


def render_ebs_charts(
    ebs_df: pd.DataFrame,
    volumes,
    *,
    cluster_state: str | None = None,
) -> None:
    st.subheader("Per-volume EBS metrics")

    aggregate_mode = bool(volumes) and all(
        getattr(vol, "cloudwatch_aggregate", False) for vol in volumes
    )

    if aggregate_mode:
        st.caption(
            "Terminated cluster: CloudWatch `AWS/EC2` instance metrics "
            "(`EBSReadBytes` / `EBSWriteBytes`, all attached volumes). "
            "Time range is aligned to the cluster lifetime when needed. "
            "`VolumeIdleTime` is unavailable without volume IDs."
        )
        volumes_df = pd.DataFrame(
            [
                {
                    "node": vol.node_name,
                    "instance_id": vol.instance_id,
                    "size_gb": vol.size_gb or None,
                }
                for vol in volumes
            ]
        )
        st.dataframe(volumes_df, width='stretch', hide_index=True)
    elif volumes:
        volumes_df = pd.DataFrame(
            [
                {
                    "node": vol.node_name,
                    "instance_id": vol.instance_id,
                    "volume_id": vol.volume_id or "(aggregate)",
                    "device": vol.device,
                    "size_gb": vol.size_gb,
                    "type": vol.volume_type,
                }
                for vol in volumes
            ]
        )
        st.caption(
            "Volume size from EC2 `DescribeVolumes` when available; for terminated "
            "clusters, size comes from EMR EBS configuration when volumes were deleted."
        )
        st.dataframe(volumes_df, width='stretch', hide_index=True)
    elif cluster_state == "TERMINATED":
        st.info(
            "No EBS metrics found in CloudWatch for this terminated cluster "
            "in the selected time range."
        )
        return

    row1_a, row1_b = st.columns(2)
    fig_tp = _plot_combined_traces(
        [
            (
                _ebs_chart(
                    ebs_df,
                    "VolumeReadBytes",
                    "EBS read throughput",
                    y_title="MiB/s",
                    transform=_ebs_throughput_mib_per_sec,
                ),
                "read",
            ),
            (
                _ebs_chart(
                    ebs_df,
                    "VolumeWriteBytes",
                    "EBS write throughput",
                    y_title="MiB/s",
                    transform=_ebs_throughput_mib_per_sec,
                ),
                "write",
            ),
        ],
        title="EBS read / write throughput",
        y_title="MiB/s",
    )
    if fig_tp:
        row1_a.plotly_chart(fig_tp, width='stretch')
    else:
        row1_a.caption("No EBS throughput data in this window.")

    fig_idle = _ebs_chart(
        ebs_df,
        "VolumeIdleTime",
        "EBS idle time",
        y_title="% idle",
        transform=_ebs_idle_percent,
    )
    if fig_idle:
        row1_b.plotly_chart(fig_idle, width='stretch')
    else:
        row1_b.caption("No EBS idle time data in this window.")


def render_cluster_logs(logs_result: ClusterLogsResult) -> None:
    st.subheader("Failed step logs (stdout + stderr)")

    failed_steps = getattr(logs_result, "failed_steps", [])

    if logs_result.dag_id:
        st.caption(f"DAG id: `{logs_result.dag_id}`")

    if not failed_steps:
        st.info(logs_result.message or "No failed steps on this cluster.")
        return

    failed_df = pd.DataFrame(
        [
            {
                "step_id": step.step_id,
                "name": step.name,
                "state": step.state,
                "started_at": (
                    step.started_at.astimezone(timezone.utc).strftime(
                        "%Y-%m-%d %H:%M:%S UTC"
                    )
                    if step.started_at
                    else ""
                ),
            }
            for step in failed_steps
        ]
    )
    st.dataframe(failed_df, width='stretch', hide_index=True)

    if logs_result.text:
        if logs_result.message:
            st.caption(logs_result.message)
        st.text_area(
            "stdout + stderr (failed steps)",
            logs_result.text,
            height=420,
            label_visibility="collapsed",
        )
        st.download_button(
            "Download failed step logs",
            logs_result.text,
            file_name=f"{logs_result.dag_id or 'cluster'}_failed_steps.log",
            mime="text/plain",
        )
    elif logs_result.message:
        st.warning(logs_result.message)


def _render_pricing_sidebar(region: str) -> None:
    st.divider()
    st.subheader("Pricing")
    static_prices = load_static_prices()
    prices_region = static_prices.get("region") or region
    prices_updated = static_prices.get("updated_at") or "never"
    st.caption(
        f"Static file: `{prices_region}` · updated {prices_updated} · "
        f"{len(static_prices.get('ec2_linux_ondemand_hourly_usd') or {})} EC2 types, "
        f"{len(static_prices.get('ebs_gb_month_usd') or {})} EBS types"
    )

    refresh_status = pricing_refresh_status()
    pricing_running = refresh_status["running"]
    if "pricing_was_refreshing" not in st.session_state:
        st.session_state.pricing_was_refreshing = False

    if pricing_running:
        st.session_state.pricing_was_refreshing = True
        st_autorefresh(interval=500, key="pricing_refresh_poll")
        spinner = _PRICING_SPINNER_FRAMES[int(time.time() * 2) % len(_PRICING_SPINNER_FRAMES)]
        st.button(
            f"{spinner} Updating prices…",
            disabled=True,
            use_container_width=True,
            key="pricing_refresh_loading_btn",
        )
        return

    if st.button("Update prices from AWS", use_container_width=True):
        if start_refresh_static_prices(prices_region):
            st.session_state.pricing_was_refreshing = True
            st.rerun()

    if st.session_state.pricing_was_refreshing:
        st.session_state.pricing_was_refreshing = False
        if refresh_status.get("error"):
            st.error(f"Price update failed: {refresh_status['error']}")
        else:
            cached_load.clear()
            st.rerun()


@st.cache_data(ttl=60, show_spinner="Fetching metrics from AWS…")
def cached_load(
    cluster_id: str,
    hours: int,
    region: str,
    environment: str,
    _cache_version: int = _LOAD_CACHE_VERSION,
):
    return load_all_metrics(cluster_id, hours, region, environment)


# --- Sidebar ---
with st.sidebar:
    st.header("Settings")
    env_options = available_environments()
    default_env = normalize_environment(st.session_state.get("environment", "forno"))
    environment = st.selectbox(
        "Environment",
        options=env_options,
        index=env_options.index(default_env),
    )
    st.session_state["environment"] = environment
    region = st.text_input("Region", value=default_region())
    cluster_id = st.text_input(
        "Cluster ID",
        value=st.session_state.get("cluster_id", ""),
        placeholder="j-XXXXXXXXXXXXX",
    ).strip()
    time_range = st.selectbox(
        "Time range",
        options=list(TIME_RANGE_HOURS.keys()),
        index=1,
    )
    auto_refresh = st.toggle("Auto-refresh (60s)", value=False)
    if st.button("Refresh now", type="primary"):
        clear_credential_cache()
        cached_load.clear()
        st.rerun()

    _render_pricing_sidebar(region)

    st.divider()
    st.subheader("AWS roles (Weep)")
    st.caption(f"EMR: `{emr_role_arn(environment)}`")
    st.caption(f"EC2: `{ec2_role_arn(environment)}`")
    st.caption(f"Logs: `{logs_base_uri(environment)}`")
    for label, arn in validate_roles(region, environment).items():
        st.caption(f"**{label} session:** {arn}")

if auto_refresh:
    st_autorefresh(interval=60_000, key="emr_monitor_autorefresh")

if not cluster_id:
    st.info("Enter an EMR cluster ID (e.g. `j-1AB2C3D4E5F6`) to load metrics.")
    st.stop()

if not re.match(CLUSTER_ID_PATTERN, cluster_id):
    st.warning("Cluster ID should look like `j-XXXXXXXXXXXXX`.")
    st.stop()

hours = TIME_RANGE_HOURS[time_range]
st.session_state["cluster_id"] = cluster_id

try:
    metrics = cached_load(cluster_id, hours, region, environment)
except Exception as exc:
    st.error(f"Failed to load metrics: {exc}")
    st.stop()

render_cluster_header(metrics.info)
render_cluster_cost(metrics.cost_estimate)
render_steps(metrics.info)
render_emr_charts(metrics.emr_df)
render_ec2_charts(metrics.ec2_df)
render_ebs_charts(
    metrics.ebs_df,
    metrics.info.volumes,
    cluster_state=metrics.info.state,
)
render_cluster_logs(metrics.logs_result)

with st.expander("Raw data (download)"):
    col_a, col_b, col_c = st.columns(3)
    if not metrics.emr_df.empty:
        col_a.download_button(
            "Download EMR metrics CSV",
            metrics.emr_df.to_csv(index=False),
            file_name=f"{cluster_id}_emr_metrics.csv",
            mime="text/csv",
        )
    if not metrics.ec2_df.empty:
        col_b.download_button(
            "Download EC2 metrics CSV",
            metrics.ec2_df.to_csv(index=False),
            file_name=f"{cluster_id}_ec2_metrics.csv",
            mime="text/csv",
        )
    if not metrics.ebs_df.empty:
        col_c.download_button(
            "Download EBS metrics CSV",
            metrics.ebs_df.to_csv(index=False),
            file_name=f"{cluster_id}_ebs_metrics.csv",
            mime="text/csv",
        )
