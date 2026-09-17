"""Ingest EMR cluster-day health → datalake_emr_health.daily_emr_cluster_health.

Reads cluster/instance identity from datalake_emr_health.emr_instance_timeline
(CUR) plus CloudWatch metrics. Cost lives in daily_emr_cluster_cost (billed
CUR) — this job does not price EC2/EBS and does not call the EMR control plane.

Uses default boto3 credentials (EMR instance profile in prod/forno) for
CloudWatch GetMetricData only.
"""

from __future__ import annotations

import argparse
import math
import statistics
import time
from collections import Counter
from collections.abc import Iterable, Iterator
from datetime import date, datetime, timedelta, timezone
from functools import partial
from typing import Any, Optional

import boto3
from botocore.config import Config
from pyspark import StorageLevel
from pyspark.sql import DataFrame, Row, Window
from pyspark.sql import functions as F
from pyspark.sql import types as T
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import spark
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.loaders.delta_loader import DeltaLoader

JOB_NAME = "load_daily_emr_cluster_health"
logger = QuintoAndarLogger(JOB_NAME)

_BOTO_RETRY = Config(retries={"max_attempts": 10, "mode": "adaptive"})

EMR_MEMORY_METRICS = [
    "MemoryTotalMB",
    "MemoryAllocatedMB",
    "YARNMemoryAvailablePercentage",
]
EC2_AVERAGE_METRICS = [
    "CPUUtilization",
]
# Byte counters are requested as Sum, never Average. Summing `Average`
# datapoints is period-dependent: identical traffic yields a 12x smaller total
# at the 1h period used for days past CloudWatch's 63-day 5-minute retention.
EC2_SUM_METRICS = [
    "NetworkIn",
    "NetworkOut",
    "EBSReadBytes",
    "EBSWriteBytes",
]

# CloudWatch GetMetricData ceilings.
# Per-request structural limits (private to each call):
MAX_CW_QUERIES_PER_CALL = 500  # hard AWS quota, not adjustable
MAX_CW_DATAPOINTS_PER_RESPONSE = (
    100_800  # beyond this the response paginates via NextToken
)

# Account-wide quotas shared with every other CloudWatch consumer in the region.
# StartTime here is always more than 3h old, so the 396,000 DPS tier applies.
CW_CALLS_PER_SECOND_QUOTA = 50
CW_DATAPOINTS_PER_SECOND_QUOTA = 396_000
# Leave a quarter of both for dashboards and other DAGs running alongside this one.
CW_QUOTA_SHARE = 0.75

# Cluster preset emr_7_12_med_general_3_workers_fleet_cluster: 2 core + 1 task
# m6g.2xlarge = 3 x 8 vCPU = 24 executor cores. 2x oversubscription evens out
# the long-lived cluster-days against the short ones.
MAX_CW_PARTITIONS = 48

EMR_QUERIES_PER_CLUSTER = len(EMR_MEMORY_METRICS)
EC2_QUERIES_PER_INSTANCE = len(EC2_AVERAGE_METRICS) + len(EC2_SUM_METRICS)


class _QuotaPacer:
    """Holds one partition's share of the account-wide CloudWatch quotas.

    Cost of a call is the greater of its request-rate cost and its datapoint
    cost, so whichever quota binds first is the one enforced.
    """

    def __init__(
        self, *, calls_per_second: float, datapoints_per_second: float
    ) -> None:
        self._seconds_per_call = 1.0 / calls_per_second
        self._datapoints_per_second = datapoints_per_second
        self._next_allowed = time.monotonic()

    def wait(self) -> None:
        delay = self._next_allowed - time.monotonic()
        if delay > 0:
            time.sleep(delay)

    def charge(self, datapoints: int) -> None:
        # AWS GetMetricData DPS is datapoints requested (metrics × periods),
        # not values returned. Sparse series still consume the full window.
        cost = max(self._seconds_per_call, datapoints / self._datapoints_per_second)
        self._next_allowed = time.monotonic() + cost


OUTPUT_SCHEMA = T.StructType(
    [
        T.StructField("id_emr_cluster", T.StringType(), False),
        T.StructField("dag_id", T.StringType(), True),
        T.StructField("cluster_name", T.StringType(), True),
        T.StructField("master_instance_type", T.StringType(), True),
        T.StructField("worker_instance_type", T.StringType(), True),
        T.StructField("worker_count", T.IntegerType(), True),
        T.StructField("cluster_uptime_minutes", T.DoubleType(), True),
        T.StructField("ec2_on_demand_hours", T.DoubleType(), True),
        T.StructField("ec2_spot_hours", T.DoubleType(), True),
        T.StructField("ec2_source", T.StringType(), True),
        T.StructField("is_ec2_estimated", T.BooleanType(), True),
        T.StructField("p50_master_cpu_percent", T.DoubleType(), True),
        T.StructField("p95_master_cpu_percent", T.DoubleType(), True),
        T.StructField("p50_worker_cpu_percent", T.DoubleType(), True),
        T.StructField("p95_worker_cpu_percent", T.DoubleType(), True),
        T.StructField("p50_yarn_memory_used_percent", T.DoubleType(), True),
        T.StructField("p95_yarn_memory_used_percent", T.DoubleType(), True),
        T.StructField("total_network_in_bytes", T.DoubleType(), True),
        T.StructField("total_network_out_bytes", T.DoubleType(), True),
        T.StructField("total_ebs_read_bytes", T.DoubleType(), True),
        T.StructField("total_ebs_write_bytes", T.DoubleType(), True),
        T.StructField("num_cw_datapoints", T.LongType(), True),
        T.StructField("cw_period_seconds", T.IntegerType(), True),
        T.StructField("ts_cluster_started", T.TimestampType(), True),
        T.StructField("ts_cluster_ended", T.TimestampType(), True),
        T.StructField("ts_load", T.TimestampType(), False),
        T.StructField("dt_cluster_run", T.DateType(), False),
    ]
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod")
    parser.add_argument("bucket", type=str, help="datalake bucket name")
    parser.add_argument(
        "dag_name", type=str, help="Airflow DAG name without bietlejuice prefix"
    )
    parser.add_argument(
        "database_base_name", type=str, help="custom_schema (emr_health)"
    )
    parser.add_argument(
        "table_name", type=str, help="target table name (daily_emr_cluster_health)"
    )
    parser.add_argument(
        "load_start_date", type=str, help="inclusive lower bound, ISO date"
    )
    parser.add_argument(
        "load_end_date", type=str, help="exclusive upper bound, ISO date"
    )
    add_validation_target_args(parser)
    return parser.parse_args()


def _cw_client(region: str) -> Any:
    return boto3.client("cloudwatch", region_name=region, config=_BOTO_RETRY)


def _period_for(day: date) -> int:
    """CloudWatch keeps 5-min data 63 days, 1-h data 455 days.

    The resolved period is persisted as cw_period_seconds. CPU percentiles over
    1h averages are a smoother statistic than over 5-min averages, so values
    either side of the boundary are not comparable without it.
    """
    return 300 if (date.today() - day).days <= 60 else 3600


def _parse_dt(value: Any) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    return None


def _as_utc_naive(dt: datetime | None) -> datetime | None:
    if dt is None:
        return None
    return dt.astimezone(timezone.utc).replace(tzinfo=None)


def _overlap_hours(
    start: datetime | None,
    end: datetime | None,
    window_start: datetime,
    window_end: datetime,
) -> tuple[float, bool]:
    """Return (hours overlapping [window_start, window_end), is_estimated)."""
    if start is None:
        return 0.0, True
    estimated = False
    if end is None:
        end = min(datetime.now(timezone.utc), window_end)
        estimated = True
    lo = max(start, window_start)
    hi = min(end, window_end)
    if hi <= lo:
        return 0.0, estimated
    return (hi - lo).total_seconds() / 3600.0, estimated


def _percentile(values: list[float], pct: float) -> float | None:
    if not values:
        return None
    if len(values) == 1:
        return float(values[0])
    try:
        return float(statistics.quantiles(values, n=100)[pct - 1])
    except statistics.StatisticsError:
        ordered = sorted(values)
        idx = min(
            len(ordered) - 1, max(0, int(round((pct / 100.0) * (len(ordered) - 1))))
        )
        return float(ordered[idx])


def _requested_datapoints(
    queries: list[dict[str, Any]], *, start: datetime, end: datetime
) -> int:
    """Count GetMetricData datapoints billed against the account DPS quota.

    AWS charges metrics × ceil(range / Period), even when the series is empty.
    A 500-query UTC day at 5-minute period is 500 × 288 = 144_000 requested.
    """
    span = (end - start).total_seconds()
    if span <= 0 or not queries:
        return 0
    total = 0
    for query in queries:
        period = int((query.get("MetricStat") or {}).get("Period") or 0)
        if period <= 0:
            continue
        total += max(1, math.ceil(span / period))
    return total


def _get_metric_data(
    cw: Any,
    queries: list[dict[str, Any]],
    *,
    start: datetime,
    end: datetime,
    pacer: _QuotaPacer,
) -> tuple[dict[str, dict[str, list]], int]:
    accumulator: dict[str, dict[str, list]] = {}
    invocations = 0

    # Slice queries into MAX_CW_QUERIES_PER_CALL chunks.
    for i in range(0, len(queries), MAX_CW_QUERIES_PER_CALL):
        chunk = queries[i : i + MAX_CW_QUERIES_PER_CALL]
        if not chunk:
            continue
        requested = _requested_datapoints(chunk, start=start, end=end)
        next_token: str | None = None
        while True:
            pacer.wait()
            kwargs: dict[str, Any] = {
                "MetricDataQueries": chunk,
                "StartTime": start,
                "EndTime": end,
                "ScanBy": "TimestampAscending",
            }
            if next_token:
                kwargs["NextToken"] = next_token

            resp = cw.get_metric_data(**kwargs)
            invocations += 1
            # First page of a query set is billed for the full request size.
            # NextToken pages still consume TPS but do not re-request DPS.
            pacer.charge(0 if next_token else requested)

            results = resp.get("MetricDataResults") or []

            for result in results:
                qid = result.get("Id")
                if not qid:
                    continue
                entry = accumulator.setdefault(qid, {"Timestamps": [], "Values": []})
                entry["Timestamps"].extend(result.get("Timestamps") or [])
                entry["Values"].extend(result.get("Values") or [])

            next_token = resp.get("NextToken")
            if not next_token:
                break

    return accumulator, invocations


def _cluster_queries(
    cluster_id: str,
    instances: list[dict[str, Any]],
    *,
    prefix: str,
    period: int,
) -> tuple[list[dict[str, Any]], dict[str, tuple[str, ...]]]:
    queries: list[dict[str, Any]] = []
    id_meta: dict[str, tuple[str, ...]] = {}
    n = 0

    for metric in EMR_MEMORY_METRICS:
        n += 1
        qid = f"{prefix}_{n}"
        id_meta[qid] = ("emr", metric)
        queries.append(
            {
                "Id": qid,
                "MetricStat": {
                    "Metric": {
                        "Namespace": "AWS/ElasticMapReduce",
                        "MetricName": metric,
                        "Dimensions": [{"Name": "JobFlowId", "Value": cluster_id}],
                    },
                    "Period": period,
                    "Stat": "Average",
                },
                "ReturnData": True,
                "Label": f"emr|{metric}",
            }
        )

    ec2_metric_stats = [(metric, "Average") for metric in EC2_AVERAGE_METRICS]
    ec2_metric_stats += [(metric, "Sum") for metric in EC2_SUM_METRICS]

    for inst in instances:
        ec2_id = inst.get("Ec2InstanceId") or ""
        role = (inst.get("InstanceGroupType") or "UNKNOWN").upper()
        if not ec2_id:
            continue
        for metric, stat in ec2_metric_stats:
            n += 1
            qid = f"{prefix}_{n}"
            id_meta[qid] = ("ec2", role, metric)
            queries.append(
                {
                    "Id": qid,
                    "MetricStat": {
                        "Metric": {
                            "Namespace": "AWS/EC2",
                            "MetricName": metric,
                            "Dimensions": [{"Name": "InstanceId", "Value": ec2_id}],
                        },
                        "Period": period,
                        "Stat": stat,
                    },
                    "ReturnData": True,
                    "Label": f"ec2|{ec2_id}|{role}|{metric}",
                }
            )

    return queries, id_meta


def _aggregate_cluster_cw(
    results: dict[str, dict[str, list]],
    id_meta: dict[str, tuple[str, ...]],
    *,
    end_bound: datetime,
) -> dict[str, Any]:
    master_cpu: list[float] = []
    worker_cpu: list[float] = []
    mem_total: dict[datetime, float] = {}
    mem_alloc: dict[datetime, float] = {}
    yarn_avail: dict[datetime, float] = {}
    network_in = 0.0
    network_out = 0.0
    ebs_read = 0.0
    ebs_write = 0.0
    n_points = 0

    for qid, meta in id_meta.items():
        data = results.get(qid)
        if not data:
            continue
        timestamps = data.get("Timestamps") or []
        values = data.get("Values") or []

        # Keep only datapoints with timestamp < end_bound.
        valid_points: list[tuple[datetime, float]] = []
        for ts_raw, val in zip(timestamps, values):
            ts = _parse_dt(ts_raw)
            if ts is not None and ts < end_bound:
                valid_points.append((ts, float(val)))

        n_points += len(valid_points)
        if not valid_points:
            continue

        if meta[0] == "emr":
            metric = meta[1]
            for ts, fval in valid_points:
                if metric == "MemoryTotalMB":
                    mem_total[ts] = fval
                elif metric == "MemoryAllocatedMB":
                    mem_alloc[ts] = fval
                elif metric == "YARNMemoryAvailablePercentage":
                    yarn_avail[ts] = fval
        elif meta[0] == "ec2":
            _, role, metric = meta
            for _ts, fval in valid_points:
                if metric == "CPUUtilization":
                    if role == "MASTER":
                        master_cpu.append(fval)
                    else:
                        worker_cpu.append(fval)
                elif metric == "NetworkIn":
                    network_in += fval
                elif metric == "NetworkOut":
                    network_out += fval
                elif metric == "EBSReadBytes":
                    ebs_read += fval
                elif metric == "EBSWriteBytes":
                    ebs_write += fval

    yarn_used: list[float] = []
    if mem_total and mem_alloc:
        for ts, total in mem_total.items():
            if total > 0 and ts in mem_alloc:
                yarn_used.append(100.0 * mem_alloc[ts] / total)
    elif yarn_avail:
        yarn_used = [max(0.0, 100.0 - v) for v in yarn_avail.values()]

    return {
        "master_cpu": master_cpu,
        "worker_cpu": worker_cpu,
        "yarn_used": yarn_used,
        "network_in": network_in,
        "network_out": network_out,
        "ebs_read": ebs_read,
        "ebs_write": ebs_write,
        "n_points": n_points,
    }


def _cluster_day_frame(load_start: date, load_end: date) -> DataFrame | None:
    """Cluster-days aggregated in Spark and partitioned into CloudWatch query batches."""
    df = spark.sql(
        f"""
        SELECT
            id_emr_cluster,
            id_ec2_instance,
            dag_id,
            cluster_name,
            instance_role,
            market,
            instance_type,
            instance_hours_in_day,
            ts_cluster_started,
            ts_cluster_ended,
            dt_cluster_run
        FROM datalake_emr_health.emr_instance_timeline
        WHERE dt_cluster_run >= DATE('{load_start.isoformat()}')
          AND dt_cluster_run < DATE('{load_end.isoformat()}')
        """
    )
    grouped = df.groupBy("id_emr_cluster", "dt_cluster_run").agg(
        F.max("dag_id").alias("dag_id"),
        F.max("cluster_name").alias("cluster_name"),
        F.max("ts_cluster_started").alias("ts_cluster_started"),
        F.max("ts_cluster_ended").alias("ts_cluster_ended"),
        F.collect_list(
            F.struct(
                F.col("id_ec2_instance").alias("Ec2InstanceId"),
                F.col("instance_role").alias("InstanceGroupType"),
                F.col("instance_type").alias("InstanceType"),
                F.when(F.col("market") == F.lit("spot"), F.lit("SPOT"))
                .otherwise(F.lit("ON_DEMAND"))
                .alias("Market"),
                F.coalesce(
                    F.col("instance_hours_in_day").cast("double"), F.lit(0.0)
                ).alias("instance_hours_in_day"),
            )
        ).alias("instances"),
    )

    days = [
        row["dt_cluster_run"]
        for row in grouped.select("dt_cluster_run").distinct().collect()
    ]
    if not days:
        return None

    # Normalise to date if returned as datetime.
    days = [d.date() if isinstance(d, datetime) else d for d in days]
    period_pairs = [F.lit(v) for day in days for v in (day, _period_for(day))]
    frame = grouped.withColumn(
        "cw_period_seconds", F.create_map(period_pairs)[F.col("dt_cluster_run")]
    )

    frame = frame.withColumn(
        "n_cw_queries",
        F.lit(EMR_QUERIES_PER_CLUSTER)
        + F.size("instances") * F.lit(EC2_QUERIES_PER_INSTANCE),
    )
    window = (
        Window.partitionBy("dt_cluster_run")
        .orderBy("id_emr_cluster")
        .rowsBetween(Window.unboundedPreceding, -1)
    )
    # A cluster-day's queries do not have to land in one call; results reassemble by query Id.
    frame = frame.withColumn(
        "queries_before", F.coalesce(F.sum("n_cw_queries").over(window), F.lit(0))
    ).withColumn(
        "batch_id",
        F.concat_ws(
            "#",
            F.col("dt_cluster_run").cast("string"),
            F.floor(F.col("queries_before") / F.lit(MAX_CW_QUERIES_PER_CALL)).cast(
                "string"
            ),
        ),
    )

    n_batches = frame.select("batch_id").distinct().count()
    n_partitions = max(1, min(n_batches, MAX_CW_PARTITIONS))
    logger.info(
        f"m=cluster_day_frame,cluster_days={frame.count()},"
        f"batches={n_batches},partitions={n_partitions}"
    )
    return frame.repartition(n_partitions, F.col("batch_id"))


def _cluster_day_partition(
    rows: Iterable[Row], *, ts_load: datetime, region: str
) -> Iterator[Row]:
    # Build the logger on the executor. The module-level logger cannot be
    # pickled through mapPartitions (spark-submit ships this file as __main__).
    log = QuintoAndarLogger(JOB_NAME)
    materialised_rows: list[dict[str, Any]] = []
    for r in rows:
        d = r.asDict()
        insts = d.get("instances") or []
        d["instances"] = [
            inst.asDict() if hasattr(inst, "asDict") else inst for inst in insts
        ]
        materialised_rows.append(d)

    if not materialised_rows:
        return

    pacer = _QuotaPacer(
        calls_per_second=CW_CALLS_PER_SECOND_QUOTA * CW_QUOTA_SHARE / MAX_CW_PARTITIONS,
        datapoints_per_second=CW_DATAPOINTS_PER_SECOND_QUOTA
        * CW_QUOTA_SHARE
        / MAX_CW_PARTITIONS,
    )

    groups: dict[tuple[date, int], list[dict[str, Any]]] = {}
    for cd in materialised_rows:
        day = cd["dt_cluster_run"]
        if isinstance(day, datetime):
            day = day.date()
        period = int(cd.get("cw_period_seconds") or _period_for(day))
        groups.setdefault((day, period), []).append(cd)

    for (day, period), cluster_days in groups.items():
        cw = _cw_client(region)
        day_start = datetime(day.year, day.month, day.day, tzinfo=timezone.utc)
        day_end = day_start + timedelta(days=1)

        batch_queries: list[dict[str, Any]] = []
        cluster_meta: list[
            tuple[dict[str, Any], dict[str, tuple[str, ...]], datetime, bool]
        ] = []

        for idx, cd in enumerate(cluster_days):
            cid = cd.get("id_emr_cluster") or ""
            insts = cd.get("instances") or []
            ended = _parse_dt(cd.get("ts_cluster_ended"))
            end_bound = min(day_end, ended or day_end)

            if end_bound <= day_start:
                cluster_meta.append((cd, {}, end_bound, True))
            else:
                prefix = f"c{idx}"
                queries, id_meta = _cluster_queries(
                    cid, insts, prefix=prefix, period=period
                )
                batch_queries.extend(queries)
                cluster_meta.append((cd, id_meta, end_bound, False))

        results: dict[str, dict[str, list]] = {}
        calls = 0
        if batch_queries:
            results, calls = _get_metric_data(
                cw, batch_queries, start=day_start, end=day_end, pacer=pacer
            )

        log.info(
            f"m=cw_batch,day={day},clusters={len(cluster_days)},"
            f"queries={len(batch_queries)},calls={calls}"
        )

        empty_aggregate = {
            "master_cpu": [],
            "worker_cpu": [],
            "yarn_used": [],
            "network_in": 0.0,
            "network_out": 0.0,
            "ebs_read": 0.0,
            "ebs_write": 0.0,
            "n_points": 0,
        }

        for cd, id_meta, end_bound, is_skipped in cluster_meta:
            cid = cd.get("id_emr_cluster")
            try:
                if is_skipped:
                    agg = empty_aggregate
                else:
                    agg = _aggregate_cluster_cw(results, id_meta, end_bound=end_bound)
                yield from _build_cluster_day_rows(cd, cw=agg, ts_load=ts_load)
            except Exception as exc:  # noqa: BLE001
                log.warning(f"m=build_cluster_day,cluster_id={cid},day={day},err={exc}")


def _build_cluster_day_rows(
    cluster_day: dict[str, Any],
    *,
    cw: dict[str, Any],
    ts_load: datetime,
) -> list[Row]:
    cluster_id = cluster_day.get("id_emr_cluster") or ""
    day = cluster_day.get("dt_cluster_run")
    if isinstance(day, datetime):
        day = day.date()
    instances = cluster_day.get("instances") or []
    if not cluster_id or day is None:
        return []

    started = _parse_dt(cluster_day.get("ts_cluster_started"))
    ended = _parse_dt(cluster_day.get("ts_cluster_ended"))
    window_start = datetime(day.year, day.month, day.day, tzinfo=timezone.utc)
    window_end = window_start + timedelta(days=1)
    cluster_hours, cluster_estimated = _overlap_hours(
        started, ended, window_start, window_end
    )
    if cluster_hours <= 0:
        # Instance-hours are concurrent capacity, not elapsed cluster time. The
        # longest-lived instance (normally MASTER) is the safest uptime proxy
        # when the cluster timeline is missing; summing would multiply uptime by
        # the cluster's node count.
        cluster_hours = max(
            (float(inst.get("instance_hours_in_day") or 0.0) for inst in instances),
            default=0.0,
        )

    master_type = ""
    worker_types: list[str] = []
    worker_ids: set[str] = set()
    od_hours = 0.0
    spot_hours = 0.0

    for inst in instances:
        itype = inst.get("InstanceType") or ""
        market_raw = (inst.get("Market") or "ON_DEMAND").upper()
        role = (inst.get("InstanceGroupType") or "").upper()
        hours = float(inst.get("instance_hours_in_day") or 0.0)
        ec2_id = inst.get("Ec2InstanceId") or ""

        if role == "MASTER":
            master_type = master_type or itype
        else:
            if itype:
                worker_types.append(itype)
            if ec2_id:
                worker_ids.add(ec2_id)

        if hours <= 0:
            continue
        if "SPOT" in market_raw:
            spot_hours += hours
        else:
            od_hours += hours

    worker_type = Counter(worker_types).most_common(1)[0][0] if worker_types else ""

    period = int(cluster_day.get("cw_period_seconds") or _period_for(day))

    uptime_minutes = cluster_hours * 60.0
    ec2_source = "cur_timeline" if instances else "missing"

    return [
        Row(
            id_emr_cluster=cluster_id,
            dag_id=cluster_day.get("dag_id"),
            cluster_name=cluster_day.get("cluster_name"),
            master_instance_type=master_type or None,
            worker_instance_type=worker_type or None,
            worker_count=len(worker_ids),
            cluster_uptime_minutes=round(uptime_minutes, 4),
            ec2_on_demand_hours=round(od_hours, 4),
            ec2_spot_hours=round(spot_hours, 4),
            ec2_source=ec2_source,
            is_ec2_estimated=bool(cluster_estimated),
            p50_master_cpu_percent=_percentile(cw["master_cpu"], 50),
            p95_master_cpu_percent=_percentile(cw["master_cpu"], 95),
            p50_worker_cpu_percent=_percentile(cw["worker_cpu"], 50),
            p95_worker_cpu_percent=_percentile(cw["worker_cpu"], 95),
            p50_yarn_memory_used_percent=_percentile(cw["yarn_used"], 50),
            p95_yarn_memory_used_percent=_percentile(cw["yarn_used"], 95),
            total_network_in_bytes=cw["network_in"] or None,
            total_network_out_bytes=cw["network_out"] or None,
            total_ebs_read_bytes=cw["ebs_read"] or None,
            total_ebs_write_bytes=cw["ebs_write"] or None,
            num_cw_datapoints=int(cw["n_points"]),
            cw_period_seconds=period,
            ts_cluster_started=_as_utc_naive(started),
            ts_cluster_ended=_as_utc_naive(ended),
            ts_load=_as_utc_naive(ts_load),
            dt_cluster_run=day,
        )
    ]


def build_health_dataframe(load_start_date: str, load_end_date: str) -> DataFrame:
    load_start = date.fromisoformat(load_start_date)
    load_end = date.fromisoformat(load_end_date)
    if load_end <= load_start:
        logger.info("m=build_health_dataframe,msg='empty window'")
        return spark.createDataFrame([], OUTPUT_SCHEMA)

    frame = _cluster_day_frame(load_start, load_end)
    if frame is None:
        logger.info("m=build_health_dataframe,msg='no cluster-days'")
        return spark.createDataFrame([], OUTPUT_SCHEMA)

    ts_load = datetime.now(timezone.utc)
    # Executors inherit no AWS region from spark.executorEnv, so resolve it on
    # the driver and ship it with the closure.
    region = boto3.session.Session().region_name
    return spark.createDataFrame(
        frame.rdd.mapPartitions(
            partial(_cluster_day_partition, ts_load=ts_load, region=region)
        ),
        OUTPUT_SCHEMA,
    )


def load_table(
    dataframe: DataFrame,
    environment: str,
    datalake_bucket: str,
    schema: str,
    table_name: str,
    target_database: Optional[str] = None,
    target_table: Optional[str] = None,
) -> None:
    logger.info(f"m=load_table,msg='loading table {schema}.{table_name}'")
    db_info = DatalakeMetastoreService.get_db_info(environment, schema, datalake_bucket)
    database_name = db_info["db_enrich_databricks"]
    database_location = db_info["db_enrich_path"]
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=table_name,
            prod_location=database_location,
            bucket=datalake_bucket,
            target_database=target_database,
            target_table=target_table,
        )
    )
    loader = DeltaLoader(spark)
    loader.load_table(
        table_name=f"{write_database_name}.{write_table_name}",
        path=f"{write_location.rstrip('/')}/{write_table_name}",
        source_df=dataframe,
        partition_by=["dt_cluster_run"],
    )


def main() -> None:
    args = parse_args()
    logger.info(
        f"m=main,msg='starting {JOB_NAME}',load_start_date={args.load_start_date},"
        f"load_end_date={args.load_end_date}"
    )
    df = build_health_dataframe(args.load_start_date, args.load_end_date).persist(
        StorageLevel.MEMORY_AND_DISK
    )
    row_count = df.count()
    # Empty day → no rows is success (plan failure handling).
    load_table(
        dataframe=df,
        environment=args.env,
        datalake_bucket=args.bucket,
        schema=args.database_base_name,
        table_name=args.table_name,
        target_database=args.target_database_name,
        target_table=args.target_table_name,
    )
    logger.info(f"m=main,msg='finished {JOB_NAME}',rows={row_count}")
    df.unpersist()


if __name__ == "__main__":
    main()
