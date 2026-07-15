"""EMR cluster discovery and CloudWatch metric fetching."""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Any

import pandas as pd
from aws import (
    client_cloudwatch_ec2,
    client_cloudwatch_emr,
    client_ec2,
    client_emr,
)
from botocore.exceptions import ClientError

EMR_PERIOD_SEC = 300

EMR_CLUSTER_METRICS = [
    "MemoryTotalMB",
    "MemoryAllocatedMB",
    "MemoryAvailableMB",
    "YARNMemoryAvailablePercentage",
    "ContainerAllocated",
    "ContainerPending",
    "AppsRunning",
    "AppsPending",
    "AppsCompleted",
    "MRUnhealthyNodes",
]

EC2_INSTANCE_METRICS = [
    "CPUUtilization",
    "NetworkIn",
    "NetworkOut",
    "StatusCheckFailed",
]

EBS_VOLUME_METRICS = [
    "VolumeReadBytes",
    "VolumeWriteBytes",
    "VolumeIdleTime",
]

# Instance-level EBS aggregates in AWS/EC2 (retained after termination).
TERMINATED_EBS_EC2_METRICS = [
    "EBSReadBytes",
    "EBSWriteBytes",
]

TERMINATED_EBS_METRIC_ALIASES = {
    "EBSReadBytes": "VolumeReadBytes",
    "EBSWriteBytes": "VolumeWriteBytes",
}

TIME_RANGE_HOURS = {
    "1h": 1,
    "3h": 3,
    "12h": 12,
    "24h": 24,
}

MAX_PARALLEL_IO_WORKERS = 16
MAX_METRIC_DATA_QUERIES = 500
MAX_LOAD_METRICS_WORKERS = 8

EMPTY_METRICS_COLUMNS = [
    "timestamp",
    "metric_name",
    "value",
    "instance_id",
    "role",
    "node_name",
    "instance_type",
    "volume_id",
]


@dataclass
class EmrEbsVolumeRef:
    device: str
    volume_id: str


@dataclass
class InstanceInfo:
    instance_id: str
    role: str
    instance_type: str
    state: str
    private_dns: str = ""
    node_name: str = ""
    started_at: datetime | None = None
    ended_at: datetime | None = None
    instance_fleet_id: str = ""
    instance_group_id: str = ""
    emr_ebs_volumes: list[EmrEbsVolumeRef] = field(default_factory=list)


ROLE_SORT_ORDER = {"MASTER": 0, "CORE": 1, "TASK": 2}


def _cluster_uses_instance_fleets(cluster: dict[str, Any]) -> bool:
    """True when the cluster is configured with instance fleets (not instance groups)."""
    collection_type = cluster.get("InstanceCollectionType", "")
    if collection_type == "INSTANCE_FLEET":
        return True
    if collection_type == "INSTANCE_GROUP":
        return False
    if cluster.get("InstanceFleets"):
        return True
    if cluster.get("InstanceGroups"):
        return False
    return False


def _instance_role_from_emr(
    inst: dict[str, Any],
    group_type_by_id: dict[str, str],
) -> str:
    """Resolve instance role from EMR list_instances (never EC2)."""
    direct_role = inst.get("InstanceGroupType") or inst.get("InstanceFleetType")
    if direct_role:
        return direct_role
    group_id = inst.get("InstanceGroupId") or inst.get("InstanceFleetId")
    if group_id:
        return group_type_by_id.get(group_id, "UNKNOWN")
    return "UNKNOWN"


def _fleet_primary_instance_type(fleet: dict[str, Any]) -> str:
    specs = fleet.get("InstanceTypeSpecifications") or []
    if not specs:
        return ""
    return specs[0].get("InstanceType", "")


def _index_ebs_specs_from_fleet(fleet: dict[str, Any]) -> dict[tuple[str, str, str], tuple[int, str]]:
    index: dict[tuple[str, str, str], tuple[int, str]] = {}
    fleet_id = fleet.get("Id", "")
    for spec in fleet.get("InstanceTypeSpecifications", []):
        instance_type = spec.get("InstanceType", "")
        for block_idx, block in enumerate(spec.get("EbsBlockDevices", [])):
            vol_spec = block.get("VolumeSpecification") or {}
            size_gb = int(vol_spec.get("SizeInGB", 0) or 0)
            volume_type = vol_spec.get("VolumeType", "gp2") or "gp2"
            device = block.get("Device") or f"/dev/sd{chr(ord('b') + block_idx)}"
            if fleet_id and size_gb > 0:
                index[(fleet_id, instance_type, device)] = (size_gb, volume_type)
    return index


def _index_ebs_specs_from_group(group: dict[str, Any]) -> dict[tuple[str, str, str], tuple[int, str]]:
    index: dict[tuple[str, str, str], tuple[int, str]] = {}
    group_id = group.get("Id", "")
    instance_type = group.get("InstanceType", "")
    for block in group.get("EbsBlockDevices", []):
        vol_spec = block.get("VolumeSpecification") or {}
        size_gb = int(vol_spec.get("SizeInGB", 0) or 0)
        volume_type = vol_spec.get("VolumeType", "gp2") or "gp2"
        device = block.get("Device", "/dev/sdb")
        if group_id and size_gb > 0:
            index[(group_id, instance_type, device)] = (size_gb, volume_type)
    return index


def _fetch_cluster_topology_from_api(
    emr: Any,
    cluster_id: str,
    *,
    uses_instance_fleets: bool,
) -> tuple[dict[str, str], str, str, int, dict[tuple[str, str, str], tuple[int, str]]]:
    """Single paginated EMR pass: role lookup, header summary, and EBS spec index."""
    lookup: dict[str, str] = {}
    master_type = ""
    core_type = ""
    core_count = 0
    ebs_index: dict[tuple[str, str, str], tuple[int, str]] = {}
    marker: str | None = None

    list_api = emr.list_instance_fleets if uses_instance_fleets else emr.list_instance_groups
    collection_key = "InstanceFleets" if uses_instance_fleets else "InstanceGroups"

    while True:
        kwargs: dict[str, Any] = {"ClusterId": cluster_id}
        if marker:
            kwargs["Marker"] = marker
        resp = list_api(**kwargs)
        for item in resp.get(collection_key, []):
            if uses_instance_fleets:
                item_id = item.get("Id", "")
                item_type = item.get("InstanceFleetType", "")
                if item_id and item_type:
                    lookup[item_id] = item_type
                instance_type = _fleet_primary_instance_type(item)
                fleet_type = item.get("InstanceFleetType", "")
                if fleet_type == "MASTER":
                    master_type = master_type or instance_type
                elif fleet_type == "CORE":
                    core_type = core_type or instance_type
                    core_count = (
                        item.get("TargetOnDemandCapacity", 0)
                        + item.get("TargetSpotCapacity", 0)
                    )
                ebs_index.update(_index_ebs_specs_from_fleet(item))
            else:
                item_id = item.get("Id", "")
                item_type = item.get("InstanceGroupType", "")
                if item_id and item_type:
                    lookup[item_id] = item_type
                instance_type = item.get("InstanceType", "")
                group_type = item.get("InstanceGroupType", "")
                if group_type == "MASTER":
                    master_type = master_type or instance_type
                elif group_type == "CORE":
                    core_type = core_type or instance_type
                    core_count = item.get("RequestedInstanceCount", 0)
                ebs_index.update(_index_ebs_specs_from_group(item))
        marker = resp.get("Marker")
        if not marker:
            break

    return lookup, master_type, core_type, core_count, ebs_index


def _paginate_list_instances(emr: Any, cluster_id: str) -> list[dict[str, Any]]:
    instances: list[dict[str, Any]] = []
    marker: str | None = None
    while True:
        kwargs: dict[str, Any] = {"ClusterId": cluster_id}
        if marker:
            kwargs["Marker"] = marker
        resp = emr.list_instances(**kwargs)
        instances.extend(resp.get("Instances", []))
        marker = resp.get("Marker")
        if not marker:
            break
    return instances


def _paginate_list_steps(emr: Any, cluster_id: str) -> list[dict[str, Any]]:
    steps: list[dict[str, Any]] = []
    marker: str | None = None
    while True:
        kwargs: dict[str, Any] = {"ClusterId": cluster_id}
        if marker:
            kwargs["Marker"] = marker
        resp = emr.list_steps(**kwargs)
        steps.extend(resp.get("Steps", []))
        marker = resp.get("Marker")
        if not marker:
            break
    return steps


def _instance_info_from_emr(
    inst: dict[str, Any],
    group_type_by_id: dict[str, str],
) -> InstanceInfo:
    timeline = inst.get("Status", {}).get("Timeline") or {}
    emr_ebs_volumes = [
        EmrEbsVolumeRef(
            device=ebs.get("Device", ""),
            volume_id=ebs.get("VolumeId", ""),
        )
        for ebs in inst.get("EbsVolumes", [])
        if ebs.get("VolumeId")
    ]
    return InstanceInfo(
        instance_id=inst.get("Ec2InstanceId", ""),
        role=_instance_role_from_emr(inst, group_type_by_id),
        instance_type=inst.get("InstanceType", ""),
        state=inst.get("Status", {}).get("State", ""),
        private_dns=inst.get("PrivateDnsName", ""),
        started_at=_parse_emr_datetime(timeline.get("CreationDateTime")),
        ended_at=_parse_emr_datetime(timeline.get("EndDateTime")),
        instance_fleet_id=inst.get("InstanceFleetId", "") or "",
        instance_group_id=inst.get("InstanceGroupId", "") or "",
        emr_ebs_volumes=emr_ebs_volumes,
    )


def _step_info_from_emr(step: dict[str, Any]) -> StepInfo:
    timeline = step.get("Status", {}).get("Timeline") or {}
    started_at = _parse_emr_datetime(
        timeline.get("StartDateTime") or timeline.get("CreationDateTime")
    )
    ended_at = _parse_emr_datetime(timeline.get("EndDateTime"))
    return StepInfo(
        step_id=step.get("Id", ""),
        name=step.get("Name", ""),
        state=step.get("Status", {}).get("State", ""),
        action_on_failure=step.get("ActionOnFailure", ""),
        started_at=started_at,
        ended_at=ended_at,
    )


def _assign_node_names(instances: list[InstanceInfo]) -> list[InstanceInfo]:
    """Label instances as Master / coreN / taskN for chart series."""
    ordered = sorted(
        instances,
        key=lambda inst: (ROLE_SORT_ORDER.get(inst.role, 99), inst.instance_id),
    )
    core_idx = 0
    task_idx = 0
    other_idx = 0
    named: list[InstanceInfo] = []

    for inst in ordered:
        if inst.role == "MASTER":
            node_name = "Master"
        elif inst.role == "CORE":
            core_idx += 1
            node_name = f"core{core_idx}"
        elif inst.role == "TASK":
            task_idx += 1
            node_name = f"task{task_idx}"
        else:
            other_idx += 1
            node_name = f"unknown{other_idx}"

        named.append(
            InstanceInfo(
                instance_id=inst.instance_id,
                role=inst.role,
                instance_type=inst.instance_type,
                state=inst.state,
                private_dns=inst.private_dns,
                node_name=node_name,
                started_at=inst.started_at,
                ended_at=inst.ended_at,
                instance_fleet_id=inst.instance_fleet_id,
                instance_group_id=inst.instance_group_id,
                emr_ebs_volumes=inst.emr_ebs_volumes,
            )
        )
    return named


@dataclass
class VolumeInfo:
    volume_id: str
    instance_id: str
    size_gb: int
    device: str
    volume_type: str = ""
    node_name: str = ""
    role: str = ""
    instance_type: str = ""
    cloudwatch_aggregate: bool = False


@dataclass
class StepInfo:
    step_id: str
    name: str
    state: str
    action_on_failure: str
    started_at: datetime | None = None
    ended_at: datetime | None = None


@dataclass
class ClusterInfo:
    cluster_id: str
    name: str
    state: str
    status_message: str
    release_label: str
    master_instance_type: str
    core_instance_type: str
    core_instance_count: int
    started_at: datetime | None = None
    ended_at: datetime | None = None
    uses_instance_fleets: bool = False
    emr_ebs_spec_index: dict[tuple[str, str, str], tuple[int, str]] = field(
        default_factory=dict
    )
    instances: list[InstanceInfo] = field(default_factory=list)
    volumes: list[VolumeInfo] = field(default_factory=list)
    steps: list[StepInfo] = field(default_factory=list)


@dataclass
class MetricsLoadResult:
    info: ClusterInfo
    emr_df: pd.DataFrame
    ec2_df: pd.DataFrame
    ebs_df: pd.DataFrame
    logs_result: Any
    cost_estimate: Any = None


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _parse_emr_datetime(raw: Any) -> datetime | None:
    if raw is None:
        return None
    if isinstance(raw, datetime):
        dt = raw
    else:
        dt = datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _cluster_timeline(cluster: dict[str, Any]) -> tuple[datetime | None, datetime | None]:
    timeline = cluster.get("Status", {}).get("Timeline") or {}
    started_at = _parse_emr_datetime(timeline.get("CreationDateTime"))
    ended_at = _parse_emr_datetime(timeline.get("EndDateTime"))
    return started_at, ended_at


def time_window(
    hours: int,
    cluster_info: ClusterInfo | None = None,
) -> tuple[datetime, datetime]:
    end = _utc_now()
    start = end - timedelta(hours=hours)

    if (
        cluster_info is None
        or cluster_info.state != "TERMINATED"
        or cluster_info.ended_at is None
    ):
        return start, end

    cluster_start = cluster_info.started_at or (
        cluster_info.ended_at - timedelta(hours=hours)
    )
    cluster_end = cluster_info.ended_at
    effective_start = max(start, cluster_start)
    effective_end = min(end, cluster_end)
    if effective_start < effective_end:
        return effective_start, effective_end

    cluster_duration = cluster_end - cluster_start
    lookback = min(timedelta(hours=hours), cluster_duration)
    if lookback.total_seconds() <= 0:
        lookback = cluster_duration
    return cluster_end - lookback, cluster_end


def discover_cluster(
    cluster_id: str,
    region: str | None = None,
    environment: str | None = None,
) -> ClusterInfo:
    emr = client_emr(region, environment)
    cluster = emr.describe_cluster(ClusterId=cluster_id)["Cluster"]
    uses_instance_fleets = _cluster_uses_instance_fleets(cluster)

    with ThreadPoolExecutor(max_workers=3) as executor:
        future_instances = executor.submit(_paginate_list_instances, emr, cluster_id)
        future_steps = executor.submit(_paginate_list_steps, emr, cluster_id)
        future_topology = executor.submit(
            _fetch_cluster_topology_from_api,
            emr,
            cluster_id,
            uses_instance_fleets=uses_instance_fleets,
        )

        raw_instances = future_instances.result()
        raw_steps = future_steps.result()
        (
            group_type_by_id,
            master_type,
            core_type,
            core_count,
            emr_ebs_spec_index,
        ) = future_topology.result()

    instances = [
        _instance_info_from_emr(inst, group_type_by_id) for inst in raw_instances
    ]
    instances = _assign_node_names(instances)
    steps = [_step_info_from_emr(step) for step in raw_steps]

    status = cluster.get("Status", {})
    started_at, ended_at = _cluster_timeline(cluster)
    return ClusterInfo(
        cluster_id=cluster_id,
        name=cluster.get("Name", ""),
        state=status.get("State", ""),
        status_message=status.get("StateChangeReason", {}).get("Message", ""),
        release_label=cluster.get("ReleaseLabel", ""),
        master_instance_type=master_type,
        core_instance_type=core_type,
        core_instance_count=core_count,
        started_at=started_at,
        ended_at=ended_at,
        uses_instance_fleets=uses_instance_fleets,
        emr_ebs_spec_index=emr_ebs_spec_index,
        instances=instances,
        steps=steps,
    )


def _metric_data_queries(
    *,
    namespace: str,
    metric_names: list[str],
    dimension_name: str,
    dimension_value: str,
    period: int,
    stat: str,
    id_prefix: str,
) -> list[dict[str, Any]]:
    return _metric_data_queries_dims(
        namespace=namespace,
        metric_names=metric_names,
        dimensions={dimension_name: dimension_value},
        period=period,
        stat=stat,
        id_prefix=id_prefix,
    )


def _metric_data_queries_dims(
    *,
    namespace: str,
    metric_names: list[str],
    dimensions: dict[str, str],
    period: int,
    stat: str,
    id_prefix: str,
) -> list[dict[str, Any]]:
    dims_list = [{"Name": key, "Value": value} for key, value in dimensions.items()]
    queries: list[dict[str, Any]] = []
    for idx, metric_name in enumerate(metric_names):
        queries.append(
            {
                "Id": f"{id_prefix}{idx}",
                "MetricStat": {
                    "Metric": {
                        "Namespace": namespace,
                        "MetricName": metric_name,
                        "Dimensions": dims_list,
                    },
                    "Period": period,
                    "Stat": stat,
                },
                "ReturnData": True,
                "Label": metric_name,
            }
        )
    return queries


def _empty_metrics_frame() -> pd.DataFrame:
    return pd.DataFrame(columns=EMPTY_METRICS_COLUMNS)


def _chunked(values: list[Any], size: int) -> list[list[Any]]:
    return [values[idx : idx + size] for idx in range(0, len(values), size)]


def _get_metric_data_chunked(
    cw: Any,
    queries: list[dict[str, Any]],
    *,
    start: datetime,
    end: datetime,
) -> list[dict[str, Any]]:
    if not queries:
        return []
    results: list[dict[str, Any]] = []
    for batch in _chunked(queries, MAX_METRIC_DATA_QUERIES):
        resp = cw.get_metric_data(
            MetricDataQueries=batch,
            StartTime=start,
            EndTime=end,
            ScanBy="TimestampAscending",
        )
        results.extend(resp.get("MetricDataResults", []))
    return results


def _volume_info_from_attachment(
    *,
    vol: dict[str, Any],
    inst_id: str,
    device: str,
    by_id: dict[str, InstanceInfo],
) -> VolumeInfo | None:
    inst = by_id.get(inst_id)
    if inst is None:
        return None
    return VolumeInfo(
        volume_id=vol.get("VolumeId", ""),
        instance_id=inst_id,
        size_gb=int(vol.get("Size", 0)),
        device=device,
        volume_type=vol.get("VolumeType", ""),
        node_name=inst.node_name,
        role=inst.role,
        instance_type=inst.instance_type,
    )


def discover_instance_volumes(
    instances: list[InstanceInfo],
    region: str | None = None,
    environment: str | None = None,
) -> list[VolumeInfo]:
    """Discover EBS volumes via EC2; role/node labels come from EMR discovery."""
    instance_ids = [inst.instance_id for inst in instances if inst.instance_id]
    if not instance_ids:
        return []

    by_id = {inst.instance_id: inst for inst in instances}
    ec2 = client_ec2(region, environment)
    volumes_by_key: dict[tuple[str, str, str], VolumeInfo] = {}

    def _ingest_describe_instances(batch: list[str]) -> None:
        try:
            resp = ec2.describe_instances(InstanceIds=batch)
        except ClientError:
            return
        for reservation in resp.get("Reservations", []):
            for instance in reservation.get("Instances", []):
                inst_id = instance.get("InstanceId", "")
                for mapping in instance.get("BlockDeviceMappings", []):
                    ebs = mapping.get("Ebs") or {}
                    vol_id = ebs.get("VolumeId", "")
                    if not vol_id:
                        continue
                    key = (vol_id, inst_id, mapping.get("DeviceName", ""))
                    if key in volumes_by_key:
                        continue
                    inst = by_id.get(inst_id)
                    if inst is None:
                        continue
                    volumes_by_key[key] = VolumeInfo(
                        volume_id=vol_id,
                        instance_id=inst_id,
                        size_gb=0,
                        device=mapping.get("DeviceName", ""),
                        volume_type="",
                        node_name=inst.node_name,
                        role=inst.role,
                        instance_type=inst.instance_type,
                    )

    instance_batches = _chunked(instance_ids, 100)
    with ThreadPoolExecutor(
        max_workers=_parallel_worker_count(len(instance_batches))
    ) as executor:
        list(executor.map(_ingest_describe_instances, instance_batches))

    def _ingest_describe_volumes(batch: list[str]) -> None:
        paginator = ec2.get_paginator("describe_volumes")
        for page in paginator.paginate(
            Filters=[{"Name": "attachment.instance-id", "Values": batch}]
        ):
            for vol in page.get("Volumes", []):
                for attachment in vol.get("Attachments", []):
                    inst_id = attachment.get("InstanceId", "")
                    device = attachment.get("Device", "")
                    key = (vol.get("VolumeId", ""), inst_id, device)
                    info = _volume_info_from_attachment(
                        vol=vol,
                        inst_id=inst_id,
                        device=device,
                        by_id=by_id,
                    )
                    if info is not None:
                        volumes_by_key[key] = info

    volume_batches = _chunked(instance_ids, 50)
    with ThreadPoolExecutor(
        max_workers=_parallel_worker_count(len(volume_batches))
    ) as executor:
        list(executor.map(_ingest_describe_volumes, volume_batches))

    volumes = list(volumes_by_key.values())
    volumes.sort(
        key=lambda vol: (
            ROLE_SORT_ORDER.get(vol.role, 99),
            vol.instance_id,
            vol.device,
        )
    )
    return volumes


def _synthetic_aggregate_volumes(
    instances: list[InstanceInfo],
) -> list[VolumeInfo]:
    """Placeholder targets for per-instance CloudWatch EBS aggregates on terminated nodes."""
    volumes: list[VolumeInfo] = []
    for inst in instances:
        if not inst.instance_id:
            continue
        volumes.append(
            VolumeInfo(
                volume_id="",
                instance_id=inst.instance_id,
                size_gb=0,
                device="(all volumes)",
                volume_type="",
                node_name=inst.node_name,
                role=inst.role,
                instance_type=inst.instance_type,
                cloudwatch_aggregate=True,
            )
        )
    volumes.sort(
        key=lambda vol: (
            ROLE_SORT_ORDER.get(vol.role, 99),
            vol.instance_id,
            vol.device,
        )
    )
    return volumes


def _build_emr_ebs_spec_index(
    emr: Any,
    *,
    cluster_id: str,
    uses_instance_fleets: bool,
) -> dict[tuple[str, str, str], tuple[int, str]]:
    """Map (fleet_or_group_id, instance_type, device) -> (size_gb, volume_type)."""
    index: dict[tuple[str, str, str], tuple[int, str]] = {}
    list_api = emr.list_instance_fleets if uses_instance_fleets else emr.list_instance_groups
    collection_key = "InstanceFleets" if uses_instance_fleets else "InstanceGroups"
    indexer = _index_ebs_specs_from_fleet if uses_instance_fleets else _index_ebs_specs_from_group
    marker: str | None = None

    while True:
        kwargs: dict[str, Any] = {"ClusterId": cluster_id}
        if marker:
            kwargs["Marker"] = marker
        resp = list_api(**kwargs)
        for item in resp.get(collection_key, []):
            index.update(indexer(item))
        marker = resp.get("Marker")
        if not marker:
            break
    return index


def _lookup_emr_ebs_spec(
    spec_index: dict[tuple[str, str, str], tuple[int, str]],
    *,
    fleet_or_group_id: str,
    instance_type: str,
    device: str,
) -> tuple[int, str]:
    if not fleet_or_group_id:
        return 0, ""

    candidates = [
        (fleet_or_group_id, instance_type, device),
        (fleet_or_group_id, instance_type, "/dev/sdb"),
    ]
    for key in candidates:
        if key in spec_index:
            return spec_index[key]

    for (group_id, itype, _device), value in spec_index.items():
        if group_id == fleet_or_group_id and itype == instance_type:
            return value
    for (group_id, _itype, dev), value in spec_index.items():
        if group_id == fleet_or_group_id and dev == device:
            return value
    return 0, ""


def _describe_volume_sizes(
    volume_ids: list[str],
    *,
    region: str | None,
    environment: str | None,
) -> dict[str, tuple[int, str]]:
    if not volume_ids:
        return {}

    ec2 = client_ec2(region, environment)
    sizes: dict[str, tuple[int, str]] = {}
    unique_ids = list(dict.fromkeys(volume_ids))

    def _describe_batch(batch: list[str]) -> dict[str, tuple[int, str]]:
        batch_sizes: dict[str, tuple[int, str]] = {}
        try:
            resp = ec2.describe_volumes(VolumeIds=batch)
        except ClientError:
            for volume_id in batch:
                try:
                    single = ec2.describe_volumes(VolumeIds=[volume_id])
                except ClientError:
                    continue
                for vol in single.get("Volumes", []):
                    vid = vol.get("VolumeId", "")
                    if vid:
                        batch_sizes[vid] = (
                            int(vol.get("Size", 0)),
                            vol.get("VolumeType", "gp2") or "gp2",
                        )
            return batch_sizes

        for vol in resp.get("Volumes", []):
            vid = vol.get("VolumeId", "")
            if vid:
                batch_sizes[vid] = (
                    int(vol.get("Size", 0)),
                    vol.get("VolumeType", "gp2") or "gp2",
                )
        return batch_sizes

    batches = _chunked(unique_ids, 50)
    with ThreadPoolExecutor(max_workers=_parallel_worker_count(len(batches))) as executor:
        for batch_sizes in executor.map(_describe_batch, batches):
            sizes.update(batch_sizes)
    return sizes


def _discover_terminated_volumes_from_emr(
    instances: list[InstanceInfo],
    *,
    cluster_id: str,
    uses_instance_fleets: bool,
    emr_ebs_spec_index: dict[tuple[str, str, str], tuple[int, str]] | None = None,
    region: str | None = None,
    environment: str | None = None,
) -> list[VolumeInfo]:
    """Resolve EBS volume IDs from EMR list_instances and sizes from EC2 or EMR config."""
    pending: list[tuple[InstanceInfo, EmrEbsVolumeRef]] = []
    for inst in instances:
        for ref in inst.emr_ebs_volumes:
            if ref.volume_id:
                pending.append((inst, ref))
    if not pending:
        return []

    spec_index = emr_ebs_spec_index or {}
    if not spec_index:
        emr = client_emr(region, environment)
        spec_index = _build_emr_ebs_spec_index(
            emr,
            cluster_id=cluster_id,
            uses_instance_fleets=uses_instance_fleets,
        )

    volume_ids_for_ec2: list[str] = []
    for inst, ref in pending:
        fleet_or_group_id = inst.instance_fleet_id or inst.instance_group_id
        size_gb, _volume_type = _lookup_emr_ebs_spec(
            spec_index,
            fleet_or_group_id=fleet_or_group_id,
            instance_type=inst.instance_type,
            device=ref.device,
        )
        if size_gb <= 0:
            volume_ids_for_ec2.append(ref.volume_id)

    described_sizes = (
        _describe_volume_sizes(
            volume_ids_for_ec2,
            region=region,
            environment=environment,
        )
        if volume_ids_for_ec2
        else {}
    )

    volumes_by_key: dict[tuple[str, str, str], VolumeInfo] = {}
    for inst, ref in pending:
        size_gb, volume_type = described_sizes.get(ref.volume_id, (0, ""))
        if size_gb <= 0:
            fleet_or_group_id = inst.instance_fleet_id or inst.instance_group_id
            size_gb, volume_type = _lookup_emr_ebs_spec(
                spec_index,
                fleet_or_group_id=fleet_or_group_id,
                instance_type=inst.instance_type,
                device=ref.device,
            )
        key = (ref.volume_id, inst.instance_id, ref.device)
        volumes_by_key[key] = VolumeInfo(
            volume_id=ref.volume_id,
            instance_id=inst.instance_id,
            size_gb=size_gb,
            device=ref.device,
            volume_type=volume_type or "gp2",
            node_name=inst.node_name,
            role=inst.role,
            instance_type=inst.instance_type,
        )

    volumes = list(volumes_by_key.values())
    volumes.sort(
        key=lambda vol: (
            ROLE_SORT_ORDER.get(vol.role, 99),
            vol.instance_id,
            vol.device,
        )
    )
    return volumes


def discover_ebs_targets(
    instances: list[InstanceInfo],
    *,
    cluster_id: str = "",
    uses_instance_fleets: bool = False,
    cluster_state: str,
    emr_ebs_spec_index: dict[tuple[str, str, str], tuple[int, str]] | None = None,
    region: str | None = None,
    environment: str | None = None,
) -> list[VolumeInfo]:
    """Resolve EBS chart targets from EC2 or EMR/CloudWatch fallbacks for terminated clusters."""
    if cluster_state != "TERMINATED":
        volumes = discover_instance_volumes(instances, region, environment)
        if volumes:
            return volumes
        return []

    if cluster_id:
        emr_volumes = _discover_terminated_volumes_from_emr(
            instances,
            cluster_id=cluster_id,
            uses_instance_fleets=uses_instance_fleets,
            emr_ebs_spec_index=emr_ebs_spec_index,
            region=region,
            environment=environment,
        )
        if emr_volumes:
            return emr_volumes
    return _synthetic_aggregate_volumes(instances)


def _results_to_dataframe(
    results: list[dict[str, Any]],
    *,
    instance_id: str | None = None,
    role: str | None = None,
    node_name: str | None = None,
    instance_type: str | None = None,
    volume_id: str | None = None,
) -> pd.DataFrame:
    rows: list[dict[str, Any]] = []
    for result in results:
        label = result.get("Label", result.get("Id", ""))
        for ts, value in zip(
            result.get("Timestamps", []),
            result.get("Values", []),
        ):
            rows.append(
                {
                    "timestamp": pd.Timestamp(ts).tz_convert("UTC")
                    if pd.Timestamp(ts).tzinfo
                    else pd.Timestamp(ts, tz="UTC"),
                    "metric_name": label,
                    "value": value,
                    "instance_id": instance_id,
                    "role": role,
                    "node_name": node_name,
                    "instance_type": instance_type,
                    "volume_id": volume_id,
                }
            )
    if not rows:
        return _empty_metrics_frame()
    return pd.DataFrame(rows)


def _parallel_worker_count(task_count: int) -> int:
    if task_count <= 0:
        return 1
    return min(MAX_PARALLEL_IO_WORKERS, task_count)


def _fetch_ec2_metrics_for_instance(
    inst: InstanceInfo,
    inst_idx: int,
    *,
    start: datetime,
    end: datetime,
    region: str | None,
    environment: str | None,
) -> pd.DataFrame:
    if not inst.instance_id:
        return _empty_metrics_frame()

    cw = client_cloudwatch_ec2(region, environment)
    queries = _metric_data_queries(
        namespace="AWS/EC2",
        metric_names=EC2_INSTANCE_METRICS,
        dimension_name="InstanceId",
        dimension_value=inst.instance_id,
        period=EMR_PERIOD_SEC,
        stat="Average",
        id_prefix=f"ec2{inst_idx}",
    )
    try:
        resp = cw.get_metric_data(
            MetricDataQueries=queries,
            StartTime=start,
            EndTime=end,
            ScanBy="TimestampAscending",
        )
    except ClientError as exc:
        raise RuntimeError(
            f"EC2 CloudWatch fetch failed for {inst.instance_id}: {exc}"
        ) from exc
    return _results_to_dataframe(
        resp.get("MetricDataResults", []),
        instance_id=inst.instance_id,
        role=inst.role,
        node_name=inst.node_name,
        instance_type=inst.instance_type,
    )


def _fetch_ebs_metrics_for_volume(
    vol: VolumeInfo,
    vol_idx: int,
    *,
    start: datetime,
    end: datetime,
    region: str | None,
    environment: str | None,
) -> pd.DataFrame:
    if not vol.volume_id:
        return _empty_metrics_frame()

    cw = client_cloudwatch_ec2(region, environment)
    queries = _metric_data_queries(
        namespace="AWS/EBS",
        metric_names=EBS_VOLUME_METRICS,
        dimension_name="VolumeId",
        dimension_value=vol.volume_id,
        period=EMR_PERIOD_SEC,
        stat="Sum",
        id_prefix=f"ebs{vol_idx}",
    )
    try:
        resp = cw.get_metric_data(
            MetricDataQueries=queries,
            StartTime=start,
            EndTime=end,
            ScanBy="TimestampAscending",
        )
    except ClientError as exc:
        raise RuntimeError(
            f"EBS CloudWatch fetch failed for {vol.volume_id}: {exc}"
        ) from exc
    return _results_to_dataframe(
        resp.get("MetricDataResults", []),
        instance_id=vol.instance_id,
        role=vol.role,
        node_name=vol.node_name,
        instance_type=vol.instance_type,
        volume_id=vol.volume_id,
    )


def _fetch_cloudwatch_aggregate_ebs_for_instance(
    vol: VolumeInfo,
    vol_idx: int,
    *,
    start: datetime,
    end: datetime,
    region: str | None,
    environment: str | None,
) -> pd.DataFrame:
    """Fetch retained AWS/EC2 EBS*Bytes metrics by InstanceId (works after termination)."""
    if not vol.instance_id:
        return _empty_metrics_frame()

    cw = client_cloudwatch_ec2(region, environment)
    queries = _metric_data_queries(
        namespace="AWS/EC2",
        metric_names=TERMINATED_EBS_EC2_METRICS,
        dimension_name="InstanceId",
        dimension_value=vol.instance_id,
        period=EMR_PERIOD_SEC,
        stat="Sum",
        id_prefix=f"tebs{vol_idx}",
    )
    try:
        resp = cw.get_metric_data(
            MetricDataQueries=queries,
            StartTime=start,
            EndTime=end,
            ScanBy="TimestampAscending",
        )
    except ClientError as exc:
        raise RuntimeError(
            f"CloudWatch aggregate EBS fetch failed for {vol.instance_id}: {exc}"
        ) from exc

    frame = _results_to_dataframe(
        resp.get("MetricDataResults", []),
        instance_id=vol.instance_id,
        role=vol.role,
        node_name=vol.node_name,
        instance_type=vol.instance_type,
        volume_id=vol.volume_id,
    )
    if frame.empty:
        return frame
    renamed = frame.copy()
    renamed["metric_name"] = renamed["metric_name"].replace(
        TERMINATED_EBS_METRIC_ALIASES
    )
    return renamed


def fetch_emr_metrics(
    cluster_id: str,
    hours: int,
    region: str | None = None,
    environment: str | None = None,
) -> pd.DataFrame:
    start, end = time_window(hours)
    cw = client_cloudwatch_emr(region, environment)
    queries = _metric_data_queries(
        namespace="AWS/ElasticMapReduce",
        metric_names=EMR_CLUSTER_METRICS,
        dimension_name="JobFlowId",
        dimension_value=cluster_id,
        period=EMR_PERIOD_SEC,
        stat="Average",
        id_prefix="emr",
    )
    try:
        resp = cw.get_metric_data(
            MetricDataQueries=queries,
            StartTime=start,
            EndTime=end,
            ScanBy="TimestampAscending",
        )
    except ClientError as exc:
        raise RuntimeError(f"EMR CloudWatch fetch failed: {exc}") from exc
    return _results_to_dataframe(resp.get("MetricDataResults", []))


def fetch_ec2_metrics(
    instances: list[InstanceInfo],
    hours: int,
    region: str | None = None,
    environment: str | None = None,
) -> pd.DataFrame:
    if not instances:
        return _empty_metrics_frame()

    start, end = time_window(hours)
    indexed_instances = [
        (inst_idx, inst)
        for inst_idx, inst in enumerate(instances)
        if inst.instance_id
    ]
    if not indexed_instances:
        return _empty_metrics_frame()

    queries: list[dict[str, Any]] = []
    context_by_id: dict[str, InstanceInfo] = {}
    for inst_idx, inst in indexed_instances:
        batch = _metric_data_queries(
            namespace="AWS/EC2",
            metric_names=EC2_INSTANCE_METRICS,
            dimension_name="InstanceId",
            dimension_value=inst.instance_id,
            period=EMR_PERIOD_SEC,
            stat="Average",
            id_prefix=f"ec2{inst_idx}",
        )
        for query in batch:
            queries.append(query)
            context_by_id[query["Id"]] = inst

    cw = client_cloudwatch_ec2(region, environment)
    try:
        results = _get_metric_data_chunked(cw, queries, start=start, end=end)
    except ClientError as exc:
        raise RuntimeError(f"EC2 CloudWatch fetch failed: {exc}") from exc

    frames: list[pd.DataFrame] = []
    for result in results:
        inst = context_by_id.get(result.get("Id", ""))
        if inst is None:
            continue
        frame = _results_to_dataframe(
            [result],
            instance_id=inst.instance_id,
            role=inst.role,
            node_name=inst.node_name,
            instance_type=inst.instance_type,
        )
        if not frame.empty:
            frames.append(frame)

    if not frames:
        return _empty_metrics_frame()
    return pd.concat(frames, ignore_index=True)


def fetch_ebs_metrics(
    volumes: list[VolumeInfo],
    hours: int,
    region: str | None = None,
    environment: str | None = None,
    *,
    cluster_info: ClusterInfo | None = None,
) -> pd.DataFrame:
    if not volumes:
        return _empty_metrics_frame()

    start, end = time_window(hours, cluster_info)
    indexed_volumes = [
        (vol_idx, vol)
        for vol_idx, vol in enumerate(volumes)
        if vol.volume_id or vol.cloudwatch_aggregate
    ]
    if not indexed_volumes:
        return _empty_metrics_frame()

    queries: list[dict[str, Any]] = []
    volume_by_id: dict[str, VolumeInfo] = {}
    aggregate_ids: set[str] = set()

    for vol_idx, vol in indexed_volumes:
        if vol.cloudwatch_aggregate:
            batch = _metric_data_queries(
                namespace="AWS/EC2",
                metric_names=TERMINATED_EBS_EC2_METRICS,
                dimension_name="InstanceId",
                dimension_value=vol.instance_id,
                period=EMR_PERIOD_SEC,
                stat="Sum",
                id_prefix=f"tebs{vol_idx}",
            )
            for query in batch:
                queries.append(query)
                aggregate_ids.add(query["Id"])
                volume_by_id[query["Id"]] = vol
        else:
            batch = _metric_data_queries(
                namespace="AWS/EBS",
                metric_names=EBS_VOLUME_METRICS,
                dimension_name="VolumeId",
                dimension_value=vol.volume_id,
                period=EMR_PERIOD_SEC,
                stat="Sum",
                id_prefix=f"ebs{vol_idx}",
            )
            for query in batch:
                queries.append(query)
                volume_by_id[query["Id"]] = vol

    cw = client_cloudwatch_ec2(region, environment)
    try:
        results = _get_metric_data_chunked(cw, queries, start=start, end=end)
    except ClientError as exc:
        raise RuntimeError(f"EBS CloudWatch fetch failed: {exc}") from exc

    frames: list[pd.DataFrame] = []
    for result in results:
        query_id = result.get("Id", "")
        vol = volume_by_id.get(query_id)
        if vol is None:
            continue
        frame = _results_to_dataframe(
            [result],
            instance_id=vol.instance_id,
            role=vol.role,
            node_name=vol.node_name,
            instance_type=vol.instance_type,
            volume_id=vol.volume_id,
        )
        if frame.empty:
            continue
        if query_id in aggregate_ids:
            renamed = frame.copy()
            renamed["metric_name"] = renamed["metric_name"].replace(
                TERMINATED_EBS_METRIC_ALIASES
            )
            frames.append(renamed)
        else:
            frames.append(frame)

    if not frames:
        return _empty_metrics_frame()
    return pd.concat(frames, ignore_index=True)


def load_all_metrics(
    cluster_id: str,
    hours: int,
    region: str | None = None,
    environment: str | None = None,
) -> MetricsLoadResult:
    from logs import fetch_cluster_logs
    from pricing import estimate_cluster_cost

    info = discover_cluster(cluster_id, region, environment)

    with ThreadPoolExecutor(max_workers=MAX_LOAD_METRICS_WORKERS) as executor:
        future_emr = executor.submit(
            fetch_emr_metrics, cluster_id, hours, region, environment
        )
        future_ec2 = executor.submit(
            fetch_ec2_metrics, info.instances, hours, region, environment
        )
        future_logs = executor.submit(
            fetch_cluster_logs, info, environment, region
        )
        future_volumes = executor.submit(
            discover_ebs_targets,
            info.instances,
            cluster_id=cluster_id,
            uses_instance_fleets=info.uses_instance_fleets,
            cluster_state=info.state,
            emr_ebs_spec_index=info.emr_ebs_spec_index,
            region=region,
            environment=environment,
        )

        info.volumes = future_volumes.result()
        future_ebs = executor.submit(
            fetch_ebs_metrics,
            info.volumes,
            hours,
            region,
            environment,
            cluster_info=info,
        )
        future_cost = executor.submit(estimate_cluster_cost, info)

        emr_df = future_emr.result()
        ec2_df = future_ec2.result()
        logs_result = future_logs.result()
        ebs_df = future_ebs.result()
        cost_estimate = future_cost.result()

    return MetricsLoadResult(
        info=info,
        emr_df=emr_df,
        ec2_df=ec2_df,
        ebs_df=ebs_df,
        logs_result=logs_result,
        cost_estimate=cost_estimate,
    )
