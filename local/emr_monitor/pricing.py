"""Estimated cluster cost from static EC2/EBS prices (bulk pricing JSON on disk)."""

from __future__ import annotations

import json
import threading
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import TYPE_CHECKING, Any
from urllib.error import URLError
from urllib.request import urlopen

if TYPE_CHECKING:
    from metrics import ClusterInfo, InstanceInfo, VolumeInfo

HOURS_PER_MONTH = 730.0
BULK_PRICING_URL = (
    "https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEC2/current/{region}/index.json"
)
_STATIC_PRICES_PATH = Path(__file__).resolve().parent / "static_prices.json"

_refresh_lock = threading.Lock()
_refresh_status: dict[str, Any] = {
    "running": False,
    "error": None,
}


@dataclass
class InstanceCostLine:
    node_name: str
    instance_id: str
    instance_type: str
    hours: float
    hourly_usd: float
    compute_cost_usd: float


@dataclass
class EbsCostLine:
    node_name: str
    volume_id: str
    volume_type: str
    size_gb: int
    hours: float
    gb_month_usd: float
    storage_cost_usd: float


@dataclass
class ClusterCostEstimate:
    total_compute_usd: float
    total_ebs_usd: float
    total_usd: float
    cluster_hours: float
    instance_lines: list[InstanceCostLine]
    ebs_lines: list[EbsCostLine]
    pricing_region: str
    prices_updated_at: str | None
    missing_instance_types: list[str]


def load_static_prices() -> dict[str, Any]:
    if not _STATIC_PRICES_PATH.is_file():
        return {
            "region": "us-east-1",
            "updated_at": None,
            "tracked_ec2_instance_types": [],
            "tracked_ebs_volume_types": [],
            "ec2_linux_ondemand_hourly_usd": {},
            "ebs_gb_month_usd": {},
        }
    return json.loads(_STATIC_PRICES_PATH.read_text(encoding="utf-8"))


def pricing_refresh_status() -> dict[str, Any]:
    with _refresh_lock:
        return dict(_refresh_status)


def start_refresh_static_prices(region: str) -> bool:
    """Fetch bulk pricing in a background thread. Returns False if already running."""
    with _refresh_lock:
        if _refresh_status["running"]:
            return False
        _refresh_status["running"] = True
        _refresh_status["error"] = None

    def _worker() -> None:
        try:
            refresh_static_prices_from_bulk(region)
            with _refresh_lock:
                _refresh_status["error"] = None
        except Exception as exc:
            with _refresh_lock:
                _refresh_status["error"] = str(exc)
        finally:
            with _refresh_lock:
                _refresh_status["running"] = False

    threading.Thread(target=_worker, daemon=True, name="pricing-refresh").start()
    return True


def _fetch_bulk_pricing_index(region: str) -> dict[str, Any]:
    url = BULK_PRICING_URL.format(region=region)
    try:
        with urlopen(url, timeout=120) as response:
            return json.load(response)
    except URLError as exc:
        raise RuntimeError(f"Failed to download bulk pricing index for {region}: {exc}") from exc


def _first_ondemand_usd(on_demand: dict[str, Any], sku: str) -> float | None:
    offer = on_demand.get(sku)
    if not offer:
        return None
    for term in offer.values():
        for dimension in term.get("priceDimensions", {}).values():
            usd = dimension.get("pricePerUnit", {}).get("USD")
            if usd is not None:
                return float(usd)
    return None


def _parse_bulk_ec2_prices(
    payload: dict[str, Any],
    tracked_instance_types: set[str],
) -> dict[str, float]:
    on_demand = payload.get("terms", {}).get("OnDemand", {})
    prices: dict[str, float] = {}

    for sku, product in payload.get("products", {}).items():
        if product.get("productFamily") != "Compute Instance":
            continue
        attrs = product.get("attributes", {})
        if attrs.get("operatingSystem") != "Linux":
            continue
        if attrs.get("tenancy") != "Shared":
            continue
        if attrs.get("preInstalledSw") != "NA":
            continue
        if attrs.get("capacitystatus") != "Used":
            continue
        if attrs.get("marketoption") != "OnDemand":
            continue

        instance_type = attrs.get("instanceType")
        if not instance_type or instance_type not in tracked_instance_types:
            continue
        if instance_type in prices:
            continue

        hourly = _first_ondemand_usd(on_demand, sku)
        if hourly is not None:
            prices[instance_type] = hourly

    return prices


def _parse_bulk_ebs_prices(
    payload: dict[str, Any],
    tracked_volume_types: set[str],
) -> dict[str, float]:
    on_demand = payload.get("terms", {}).get("OnDemand", {})
    prices: dict[str, float] = {}

    for sku, product in payload.get("products", {}).items():
        if product.get("productFamily") != "Storage":
            continue
        attrs = product.get("attributes", {})
        volume_type = attrs.get("volumeApiName") or attrs.get("volumeType")
        if not volume_type or volume_type not in tracked_volume_types:
            continue
        if volume_type in prices:
            continue

        gb_month = _first_ondemand_usd(on_demand, sku)
        if gb_month is not None:
            prices[volume_type] = gb_month

    return prices


def refresh_static_prices_from_bulk(region: str) -> dict[str, Any]:
    """Download bulk pricing and overwrite ``static_prices.json``."""
    current = load_static_prices()
    tracked_ec2 = set(current.get("tracked_ec2_instance_types") or [])
    tracked_ebs = set(current.get("tracked_ebs_volume_types") or [])
    if not tracked_ec2 or not tracked_ebs:
        raise RuntimeError(
            f"{_STATIC_PRICES_PATH.name} is missing tracked instance or volume types."
        )

    payload = _fetch_bulk_pricing_index(region)
    out = {
        "region": region,
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "source": "aws-bulk-pricing-api",
        "tracked_ec2_instance_types": sorted(tracked_ec2),
        "tracked_ebs_volume_types": sorted(tracked_ebs),
        "ec2_linux_ondemand_hourly_usd": dict(
            sorted(_parse_bulk_ec2_prices(payload, tracked_ec2).items())
        ),
        "ebs_gb_month_usd": dict(
            sorted(_parse_bulk_ebs_prices(payload, tracked_ebs).items())
        ),
    }
    _STATIC_PRICES_PATH.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
    return out


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _cluster_runtime_hours(cluster: ClusterInfo) -> float:
    if cluster.started_at is None:
        return 0.0
    end = cluster.ended_at or _utc_now()
    return max((end - cluster.started_at.astimezone(timezone.utc)).total_seconds() / 3600.0, 0.0)


def _instance_runtime_hours(instance: InstanceInfo, cluster: ClusterInfo) -> float:
    start = instance.started_at or cluster.started_at
    if start is None:
        return _cluster_runtime_hours(cluster)
    if instance.ended_at is not None:
        end = instance.ended_at
    elif cluster.state in {"TERMINATED", "TERMINATING"} and cluster.ended_at is not None:
        end = cluster.ended_at
    else:
        end = _utc_now()
    return max((end - start.astimezone(timezone.utc)).total_seconds() / 3600.0, 0.0)


def _volume_runtime_hours(volume: VolumeInfo, cluster: ClusterInfo) -> float:
    by_instance = {instance.instance_id: instance for instance in cluster.instances}
    instance = by_instance.get(volume.instance_id)
    if instance is not None:
        return _instance_runtime_hours(instance, cluster)
    return _cluster_runtime_hours(cluster)


def estimate_cluster_cost(cluster: ClusterInfo) -> ClusterCostEstimate:
    cluster_hours = _cluster_runtime_hours(cluster)
    static_prices = load_static_prices()
    prices_region = static_prices.get("region") or "us-east-1"
    ec2_rates: dict[str, float] = static_prices.get("ec2_linux_ondemand_hourly_usd") or {}
    ebs_rates: dict[str, float] = static_prices.get("ebs_gb_month_usd") or {}
    prices_updated_at = static_prices.get("updated_at")

    instance_lines: list[InstanceCostLine] = []
    missing_types: set[str] = set()
    total_compute = 0.0

    for instance in cluster.instances:
        if not instance.instance_type:
            continue
        hourly = ec2_rates.get(instance.instance_type)
        if hourly is None:
            missing_types.add(instance.instance_type)
            continue
        hours = _instance_runtime_hours(instance, cluster)
        compute_cost = hours * hourly
        total_compute += compute_cost
        instance_lines.append(
            InstanceCostLine(
                node_name=instance.node_name,
                instance_id=instance.instance_id,
                instance_type=instance.instance_type,
                hours=hours,
                hourly_usd=hourly,
                compute_cost_usd=compute_cost,
            )
        )

    ebs_lines: list[EbsCostLine] = []
    total_ebs = 0.0

    for volume in cluster.volumes:
        if volume.size_gb <= 0:
            continue
        volume_type = volume.volume_type or "gp2"
        gb_month = ebs_rates.get(volume_type)
        if gb_month is None:
            continue
        hours = _volume_runtime_hours(volume, cluster)
        storage_cost = volume.size_gb * gb_month * (hours / HOURS_PER_MONTH)
        total_ebs += storage_cost
        ebs_lines.append(
            EbsCostLine(
                node_name=volume.node_name,
                volume_id=volume.volume_id,
                volume_type=volume_type,
                size_gb=volume.size_gb,
                hours=hours,
                gb_month_usd=gb_month,
                storage_cost_usd=storage_cost,
            )
        )

    instance_lines.sort(key=lambda line: (line.node_name, line.instance_id))
    ebs_lines.sort(key=lambda line: (line.node_name, line.volume_id))

    return ClusterCostEstimate(
        total_compute_usd=total_compute,
        total_ebs_usd=total_ebs,
        total_usd=total_compute + total_ebs,
        cluster_hours=cluster_hours,
        instance_lines=instance_lines,
        ebs_lines=ebs_lines,
        pricing_region=prices_region,
        prices_updated_at=prices_updated_at,
        missing_instance_types=sorted(missing_types),
    )
