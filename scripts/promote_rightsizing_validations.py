#!/usr/bin/env python3
"""Promotion gate and post-promotion watch for cluster right-sizing validations.

Reads enrich_rightsizing_outcomes rows from a Trino-exported CSV, rewrites
*_cluster.yml files (promote validation spec to prod or remove stale blocks),
writes a markdown report, and optionally watches recently promoted DAGs.

Usage
-----
  uv run --python 3.12 python scripts/promote_rightsizing_validations.py \\
      --outcomes-csv /tmp/enrich_rightsizing_outcomes.csv \\
      --report-out /tmp/promotion_report.md

  uv run --python 3.12 python scripts/promote_rightsizing_validations.py \\
      --watch --outcomes-csv /tmp/enrich_rightsizing_outcomes.csv \\
      --ledger scripts/rightsizing_promotion_ledger.json
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from dataclasses import asdict, dataclass
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import yaml

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DAGS_ROOT = REPO_ROOT / "dags"
DEFAULT_LEDGER_PATH = REPO_ROOT / "scripts" / "rightsizing_promotion_ledger.json"

SLA_CADENCE_MAX_INTERVAL_MIN = 120.0
REGRESSION_TOLERANCE_PCT = 5.0
STRONG_POSITIVE_COST_PCT = -15.0
MEM_WARN_THRESHOLD = 82.0
COST_REGRESSION_PCT = 15.0
VALIDATION_EXTEND_MAX_DAYS = 14
WATCH_WINDOW_DAYS = 7

_CLUSTER_TAIL_KEYS = ("spark_session_configs",)


@dataclass(frozen=True)
class PromotionDecision:
    dag_id: str
    action: str
    outcome: str
    reason: str


@dataclass
class PromotionLedgerEntry:
    dag_id: str
    promoted_at: str
    previous_cluster_spec: dict[str, Any]
    baseline: dict[str, Any]


def _ensure_bietlejuice_import_path() -> None:
    compiler_root = REPO_ROOT / "packages" / "bietlejuice-compiler"
    core_src = REPO_ROOT / "packages" / "bietlejuice-core" / "src"
    for subpath in (compiler_root, compiler_root / "src", core_src):
        path_str = str(subpath)
        while path_str in sys.path:
            sys.path.remove(path_str)
        sys.path.insert(0, path_str)


def _rightsizing_validation_module():
    _ensure_bietlejuice_import_path()
    scripts_mod = sys.modules.get("scripts")
    if scripts_mod is not None and not hasattr(scripts_mod, "ci_cd"):
        del sys.modules["scripts"]
    from scripts.ci_cd.airflow_dag_builder import (  # noqa: PLC0415
        rightsizing_validation_config as rvc,
    )

    return rvc


def _wonka_config_paths_module():
    """Load wonka_config_paths after compiler scripts are on sys.path."""
    _ensure_bietlejuice_import_path()
    scripts_mod = sys.modules.get("scripts")
    if scripts_mod is not None and not hasattr(scripts_mod, "ci_cd"):
        del sys.modules["scripts"]
    from scripts.ci_cd.airflow_dag_builder import wonka_config_paths  # noqa: PLC0415

    return wonka_config_paths


def _resolve_quintoml_root(
    explicit: Path | None,
    dag_ids: list[str],
) -> Path | None:
    """Resolve QuintoML root for Wonka promotion when needed."""
    if explicit is not None:
        return explicit
    if any(dag_id.startswith("quintoml.wonka.") for dag_id in dag_ids):
        return _wonka_config_paths_module().DEFAULT_QUINTOML_ROOT
    return None


def _f(value: Any) -> float | None:
    if value is None:
        return None
    text = str(value).strip()
    if text in ("", "None", "nan", "NaN"):
        return None
    return float(text)


def _i(value: Any, default: int = 0) -> int:
    parsed = _f(value)
    if parsed is None:
        return default
    return int(parsed)


def _parse_date(value: Any) -> date | None:
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    return date.fromisoformat(text[:10])


def _row_date(row: dict[str, Any]) -> date | None:
    return _parse_date(row.get("val_dt")) or _parse_date(row.get("dt"))


def _parse_ts(value: Any) -> datetime | None:
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    normalized = text.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _row_sort_key(row: dict[str, Any]) -> tuple[date, datetime, str]:
    """Order validation runs: calendar day, then execution time, then run id."""
    row_day = _row_date(row) or date.min
    ts = _parse_ts(row.get("val_ts_started"))
    ts_key = ts if ts is not None else datetime.min.replace(tzinfo=timezone.utc)
    run_id = str(row.get("validation_airflow_run_id") or "")
    return row_day, ts_key, run_id


def _has_validation_run_grain(rows: list[dict[str, Any]]) -> bool:
    return any(str(row.get("validation_airflow_run_id") or "").strip() for row in rows)


def _mem_p95_max(row: dict[str, Any], prefix: str = "val") -> float | None:
    driver = _f(row.get(f"{prefix}_drv_mem_p95"))
    worker = _f(row.get(f"{prefix}_wrk_mem_p95"))
    if driver is None and worker is None:
        explicit = _f(row.get(f"{prefix}_mem_p95_max"))
        return explicit
    return max(v for v in (driver, worker) if v is not None)


def _delta_cost_pct(row: dict[str, Any]) -> float | None:
    explicit = _f(row.get("delta_cost_pct"))
    if explicit is not None:
        return explicit
    prod_cost = _f(row.get("prod_avg_cost_usd"))
    val_cost = _f(row.get("val_avg_cost_usd"))
    if prod_cost is None or val_cost is None or prod_cost <= 0:
        return None
    return (val_cost - prod_cost) / prod_cost * 100.0


def _cost_exceeds_tolerance(row: dict[str, Any]) -> bool:
    delta = _delta_cost_pct(row)
    if delta is None:
        return False
    return delta > REGRESSION_TOLERANCE_PCT


def _wall_passes(row: dict[str, Any]) -> bool:
    interval = _f(row.get("schedule_interval_minutes")) or 1440.0
    prod_wall_p50 = _f(row.get("prod_wall_p50_min"))
    prod_wall_p95 = _f(row.get("prod_wall_p95_min"))
    val_wall_p50 = _f(row.get("val_wall_p50_min"))
    val_wall_p95 = _f(row.get("val_wall_p95_min"))
    wall_tolerance = 1.0 + REGRESSION_TOLERANCE_PCT / 100.0

    if interval > SLA_CADENCE_MAX_INTERVAL_MIN:
        if prod_wall_p50 is None or val_wall_p50 is None or prod_wall_p50 <= 0:
            return False
        return val_wall_p50 <= prod_wall_p50 * wall_tolerance

    if prod_wall_p95 is None or val_wall_p95 is None:
        return False
    sla_limit = max(0.8 * interval, prod_wall_p95 * wall_tolerance)
    return val_wall_p95 <= sla_limit


def _row_has_validation_activity(row: dict[str, Any]) -> bool:
    return _i(row.get("val_run_count")) > 0 or _i(row.get("val_clean_run_count")) > 0


def _has_strong_positive_signal(row: dict[str, Any]) -> bool:
    """Observed savings or acceptable wall despite incomplete pairing (extend rows)."""
    if _i(row.get("val_failure_count")) > 0:
        return False
    delta = _delta_cost_pct(row)
    if delta is not None and delta <= STRONG_POSITIVE_COST_PCT:
        return True
    if delta is not None and delta <= REGRESSION_TOLERANCE_PCT and _wall_passes(row):
        return True
    return False


def decide_promotion_action(
    row: dict[str, Any],
    *,
    validation_age_days: int | None = None,
) -> PromotionDecision:
    """Return promote / reject / extend for one outcomes row."""
    dag_id = str(row.get("prod_airflow_dag_id") or row.get("dag_id") or "").strip()
    val_failure_count = _i(row.get("val_failure_count"))
    val_clean_run_count = _i(row.get("val_clean_run_count"))
    mem_p95 = _mem_p95_max(row, prefix="val")

    if val_failure_count > 0:
        return PromotionDecision(
            dag_id=dag_id,
            action="reject",
            outcome="fail",
            reason="validation run had task or Databricks failure",
        )

    if val_clean_run_count < 1:
        if (
            validation_age_days is not None
            and validation_age_days >= VALIDATION_EXTEND_MAX_DAYS
        ):
            return PromotionDecision(
                dag_id=dag_id,
                action="reject",
                outcome="fail",
                reason=(
                    f"no clean validation run after {validation_age_days} days; "
                    "freeing validation slot"
                ),
            )
        return PromotionDecision(
            dag_id=dag_id,
            action="extend",
            outcome="extend",
            reason="awaiting first successful validation run",
        )

    if _cost_exceeds_tolerance(row):
        return PromotionDecision(
            dag_id=dag_id,
            action="reject",
            outcome="fail",
            reason=(
                f"validation cost exceeds prod baseline by more than "
                f"{REGRESSION_TOLERANCE_PCT:.0f}%"
            ),
        )

    if not _wall_passes(row):
        return PromotionDecision(
            dag_id=dag_id,
            action="reject",
            outcome="fail",
            reason="validation wall time exceeds cadence-aware threshold",
        )

    if mem_p95 is not None and mem_p95 > MEM_WARN_THRESHOLD:
        return PromotionDecision(
            dag_id=dag_id,
            action="extend",
            outcome="warn",
            reason=f"validation memory P95 {mem_p95:.1f}% exceeds {MEM_WARN_THRESHOLD:.0f}% guard",
        )

    return PromotionDecision(
        dag_id=dag_id,
        action="promote",
        outcome="pass",
        reason="clean validation run with acceptable cost and wall time",
    )


def decisive_row_for_dag(
    rows: list[dict[str, Any]],
    dag_id: str,
    *,
    validation_age_days: int | None = None,
) -> dict[str, Any] | None:
    """Newest validation run with a decisive signal (promote/reject/warn or strong extend)."""
    ordered = _rows_for_dag(rows, dag_id)
    if not ordered:
        return None

    active = [
        (
            row,
            decide_promotion_action(row, validation_age_days=validation_age_days),
        )
        for row in ordered
        if _row_has_validation_activity(row)
    ]
    if not active:
        return ordered[-1]

    for row, decision in reversed(active):
        if decision.action in ("promote", "reject") or decision.outcome == "warn":
            return row

    for row, decision in reversed(active):
        if decision.outcome == "extend" and _has_strong_positive_signal(row):
            return row

    return ordered[-1]


def decisive_row_per_dag(rows: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    decisive: dict[str, dict[str, Any]] = {}
    dag_ids = {
        str(row.get("prod_airflow_dag_id") or row.get("dag_id") or "").strip()
        for row in rows
    }
    dag_ids.discard("")
    for dag_id in dag_ids:
        row = decisive_row_for_dag(rows, dag_id)
        if row is not None:
            decisive[dag_id] = row
    return decisive


def _rows_for_dag(rows: list[dict[str, Any]], dag_id: str) -> list[dict[str, Any]]:
    matched = [
        row
        for row in rows
        if str(row.get("prod_airflow_dag_id") or row.get("dag_id") or "").strip()
        == dag_id
    ]
    return sorted(matched, key=_row_sort_key)


def decide_promotion_for_dag(
    rows: list[dict[str, Any]],
    dag_id: str,
    *,
    validation_age_days: int | None = None,
) -> tuple[PromotionDecision, dict[str, Any] | None]:
    """Return one promotion decision for a DAG; returns (decision, deciding row).

    Picks the newest decisive validation signal: promote, reject, warn, or a
    strong-positive extend (post-fix improvement). Falls back to the latest row
    when every attempt is a plain extend.
    """
    row = decisive_row_for_dag(
        rows, dag_id, validation_age_days=validation_age_days
    )
    if row is None:
        return (
            PromotionDecision(
                dag_id=dag_id,
                action="extend",
                outcome="extend",
                reason="no outcomes rows for DAG",
            ),
            None,
        )
    return (
        decide_promotion_action(row, validation_age_days=validation_age_days),
        row,
    )


def load_outcomes_csv(path: Path) -> list[dict[str, Any]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def latest_row_per_dag(rows: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    latest: dict[str, dict[str, Any]] = {}
    for row in rows:
        dag_id = str(row.get("prod_airflow_dag_id") or row.get("dag_id") or "").strip()
        if not dag_id:
            continue
        existing = latest.get(dag_id)
        if existing is None or _row_sort_key(row) >= _row_sort_key(existing):
            latest[dag_id] = row
    return latest


def validation_age_days(rows: list[dict[str, Any]], dag_id: str) -> int | None:
    dated_rows = [
        (_row_date(row), row)
        for row in rows
        if str(row.get("prod_airflow_dag_id") or row.get("dag_id") or "").strip()
        == dag_id
    ]
    dated_rows = [(dt, row) for dt, row in dated_rows if dt is not None]
    if not dated_rows:
        return None

    first_val_activity: date | None = None
    for dt, row in sorted(dated_rows, key=lambda item: item[0]):
        if _i(row.get("val_run_count")) > 0 or _i(row.get("val_clean_run_count")) > 0:
            first_val_activity = dt
            break
    if first_val_activity is None:
        return None

    latest_dt = max(dt for dt, _ in dated_rows)
    return (latest_dt - first_val_activity).days


def prod_baseline_snapshot(
    rows: list[dict[str, Any]],
    dag_id: str,
    *,
    as_of: date | None = None,
    lookback_days: int = 14,
) -> dict[str, Any]:
    dated_rows = [
        (dt, row)
        for dt, row in (
            (_row_date(row), row)
            for row in rows
            if str(row.get("prod_airflow_dag_id") or row.get("dag_id") or "").strip()
            == dag_id
        )
        if dt is not None and (as_of is None or dt <= as_of)
    ]
    if as_of is not None:
        cutoff = as_of - timedelta(days=lookback_days)
        dated_rows = [(dt, row) for dt, row in dated_rows if dt >= cutoff]

    if not dated_rows:
        return {}

    costs = [_f(row.get("prod_avg_cost_usd")) for _, row in dated_rows]
    wall_p50 = [_f(row.get("prod_wall_p50_min")) for _, row in dated_rows]
    wall_p95 = [_f(row.get("prod_wall_p95_min")) for _, row in dated_rows]
    mem_vals = [_mem_p95_max(row, prefix="prod") for _, row in dated_rows]
    intervals = [_f(row.get("schedule_interval_minutes")) for _, row in dated_rows]
    failures = [_i(row.get("prod_failure_count")) for _, row in dated_rows]

    def _avg(values: list[float | None]) -> float | None:
        present = [v for v in values if v is not None]
        if not present:
            return None
        return round(sum(present) / len(present), 6)

    return {
        "avg_cost_usd": _avg(costs),
        "wall_p50_min": _avg(wall_p50),
        "wall_p95_min": _avg(wall_p95),
        "mem_p95_max": _avg(mem_vals),
        "schedule_interval_minutes": _avg(intervals),
        "failure_count": sum(failures),
        "lookback_days": lookback_days,
        "snapshot_through": as_of.isoformat() if as_of else None,
    }


def baseline_from_deciding_row(row: dict[str, Any]) -> dict[str, Any]:
    """Snapshot reference-prod metrics from a validation-run outcomes row."""
    row_day = _row_date(row)
    return {
        "avg_cost_usd": _f(row.get("prod_avg_cost_usd")),
        "wall_p50_min": _f(row.get("prod_wall_p50_min")),
        "wall_p95_min": _f(row.get("prod_wall_p95_min")),
        "mem_p95_max": _mem_p95_max(row, prefix="prod"),
        "schedule_interval_minutes": _f(row.get("schedule_interval_minutes")),
        "failure_count": _i(row.get("prod_failure_count")),
        "snapshot_through": row_day.isoformat() if row_day else None,
    }


def _cluster_tail_sections(text: str, rvc: Any) -> list[str]:
    sections: list[str] = []
    for key in _CLUSTER_TAIL_KEYS:
        section = rvc._extract_top_level_section_text(text, key)
        if section:
            sections.append(section.rstrip("\n"))
    return sections


def promote_validation_cluster_file(cluster_path: Path) -> dict[str, Any] | None:
    """Move validation.cluster into prod cluster block and drop validation:."""
    rvc = _rightsizing_validation_module()
    from scripts.ci_cd.airflow_dag_builder.cluster_yaml_format import (  # noqa: PLC0415
        dump_cluster_yaml,
    )

    if not cluster_path.exists():
        return None

    original_text = cluster_path.read_text(encoding="utf-8")
    doc = yaml.safe_load(original_text) or {}
    if not isinstance(doc, dict) or "validation" not in doc:
        return None

    previous_cluster = doc.get("cluster", {})
    validation_cluster = doc["validation"].get("cluster")
    if not isinstance(validation_cluster, dict):
        return None

    validation_text = rvc._extract_top_level_section_text(original_text, "validation")
    text_without_validation = (
        original_text.replace(validation_text, "") if validation_text else original_text
    )

    new_cluster_yaml = dump_cluster_yaml({"cluster": validation_cluster}).rstrip("\n")
    cluster_text = rvc._extract_top_level_section_text(
        text_without_validation, "cluster"
    )
    if cluster_text:
        new_text = text_without_validation.replace(
            cluster_text, new_cluster_yaml + "\n"
        )
    else:
        new_text = new_cluster_yaml + "\n" + text_without_validation

    tail_sections = _cluster_tail_sections(text_without_validation, rvc)
    new_text = new_text.rstrip("\n") + "\n"
    if tail_sections:
        new_text = new_text.rstrip("\n") + "\n" + "\n".join(tail_sections) + "\n"

    cluster_path.write_text(
        rvc._normalize_cluster_file_text(new_text), encoding="utf-8"
    )
    return previous_cluster if isinstance(previous_cluster, dict) else {}


def remove_validation_cluster_file(cluster_path: Path) -> bool:
    rvc = _rightsizing_validation_module()
    return rvc.remove_validation_from_cluster_file(cluster_path)


def _wonka_validation_module():
    _ensure_bietlejuice_import_path()
    scripts_mod = sys.modules.get("scripts")
    if scripts_mod is not None and not hasattr(scripts_mod, "ci_cd"):
        del sys.modules["scripts"]
    from scripts.ci_cd.airflow_dag_builder import (  # noqa: PLC0415
        wonka_validation_config as wvc,
    )

    return wvc


def resolve_config_path(
    dag_id: str,
    *,
    dags_root: Path,
    quintoml_root: Path | None,
) -> tuple[Path | None, str]:
    """Return (config_path, source) where source is bietlejuice or wonka."""
    rvc = _rightsizing_validation_module()
    if dag_id.startswith("quintoml.wonka."):
        effective_root = quintoml_root
        if effective_root is None:
            effective_root = _wonka_config_paths_module().DEFAULT_QUINTOML_ROOT
        config_path = rvc.dag_id_to_config_path(
            dag_id,
            dags_root=dags_root,
            quintoml_root=effective_root,
        )
        return config_path, "wonka"
    dag_name = dag_id.removeprefix("bietlejuice.")
    config_path = rvc.find_dag_cluster_path(dag_name, dags_root)
    return config_path, "bietlejuice"


def promote_validation_config_file(
    config_path: Path,
    *,
    source: str,
) -> dict[str, Any] | None:
    if source == "wonka":
        wvc = _wonka_validation_module()
        return wvc.promote_wonka_validation_to_prod(config_path)
    return promote_validation_cluster_file(config_path)


def remove_validation_config_file(config_path: Path, *, source: str) -> bool:
    if source == "wonka":
        wvc = _wonka_validation_module()
        return wvc.remove_validation_from_wonka_prod_yml(config_path)
    return remove_validation_cluster_file(config_path)


def load_ledger(path: Path) -> list[PromotionLedgerEntry]:
    if not path.exists():
        return []
    payload = json.loads(path.read_text(encoding="utf-8"))
    entries = payload.get("entries", payload if isinstance(payload, list) else [])
    return [
        PromotionLedgerEntry(
            dag_id=str(item["dag_id"]),
            promoted_at=str(item["promoted_at"]),
            previous_cluster_spec=dict(item.get("previous_cluster_spec") or {}),
            baseline=dict(item.get("baseline") or {}),
        )
        for item in entries
    ]


def save_ledger(path: Path, entries: list[PromotionLedgerEntry]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {"entries": [asdict(entry) for entry in entries]}
    path.write_text(
        json.dumps(payload, indent=2, sort_keys=False) + "\n", encoding="utf-8"
    )


def apply_promotions(
    rows: list[dict[str, Any]],
    *,
    dags_root: Path = DEFAULT_DAGS_ROOT,
    quintoml_root: Path | None = None,
    ledger_path: Path = DEFAULT_LEDGER_PATH,
    dry_run: bool = False,
) -> tuple[list[PromotionDecision], list[PromotionLedgerEntry]]:
    dag_ids = sorted(latest_row_per_dag(rows))
    quintoml_root = _resolve_quintoml_root(quintoml_root, dag_ids)
    decisions: list[PromotionDecision] = []
    ledger = load_ledger(ledger_path)

    for dag_id in dag_ids:
        age_days = validation_age_days(rows, dag_id)
        decision, row = decide_promotion_for_dag(
            rows, dag_id, validation_age_days=age_days
        )
        if row is None:
            decisions.append(decision)
            continue
        decisions.append(decision)

        config_path, source = resolve_config_path(
            dag_id,
            dags_root=dags_root,
            quintoml_root=quintoml_root,
        )
        if config_path is None or not config_path.exists():
            decision = PromotionDecision(
                dag_id=dag_id,
                action=decision.action,
                outcome=decision.outcome,
                reason=f"{decision.reason}; cluster config not found",
            )
            decisions[-1] = decision
            continue

        if dry_run:
            continue

        if decision.action == "promote":
            previous_cluster = promote_validation_config_file(
                config_path, source=source
            )
            if previous_cluster is None:
                decision = PromotionDecision(
                    dag_id=dag_id,
                    action="extend",
                    outcome="extend",
                    reason="config file has no validation block to promote",
                )
                decisions[-1] = decision
                continue
            as_of = _row_date(row) or date.today()
            if _has_validation_run_grain([row]):
                baseline = baseline_from_deciding_row(row)
            else:
                baseline = prod_baseline_snapshot(rows, dag_id, as_of=as_of)
            ledger.append(
                PromotionLedgerEntry(
                    dag_id=dag_id,
                    promoted_at=as_of.isoformat(),
                    previous_cluster_spec=previous_cluster,
                    baseline=baseline,
                )
            )
        elif decision.action == "reject":
            remove_validation_config_file(config_path, source=source)

    if not dry_run:
        save_ledger(ledger_path, ledger)
    return decisions, ledger


def render_report(decisions: list[PromotionDecision]) -> str:
    groups: dict[str, list[PromotionDecision]] = {
        "promote": [],
        "reject": [],
        "extend": [],
    }
    for decision in decisions:
        groups.setdefault(decision.action, []).append(decision)

    lines = [
        "# Rightsizing validation promotion report",
        "",
        f"Generated at {datetime.utcnow().isoformat(timespec='seconds')}Z",
        "",
    ]
    for action in ("promote", "reject", "extend"):
        lines.append(f"## {action.title()} ({len(groups.get(action, []))})")
        lines.append("")
        if not groups.get(action):
            lines.append("_None_")
            lines.append("")
            continue
        for decision in groups[action]:
            lines.append(f"- `{decision.dag_id}` — {decision.reason}")
        lines.append("")
    return "\n".join(lines)


def _cadence_sla_breach(row: dict[str, Any], baseline: dict[str, Any]) -> str | None:
    interval = (
        _f(row.get("schedule_interval_minutes"))
        or _f(baseline.get("schedule_interval_minutes"))
        or 1440.0
    )
    prod_wall_p95 = _f(row.get("prod_wall_p95_min"))
    if prod_wall_p95 is None:
        return None
    if interval > SLA_CADENCE_MAX_INTERVAL_MIN:
        return None
    sla_limit = max(0.8 * interval, _f(baseline.get("wall_p95_min")) or prod_wall_p95)
    if prod_wall_p95 > sla_limit:
        return (
            f"prod wall P95 {prod_wall_p95:.1f}m exceeds cadence SLA {sla_limit:.1f}m"
        )
    return None


def watch_promotions(
    rows: list[dict[str, Any]],
    ledger_path: Path = DEFAULT_LEDGER_PATH,
    *,
    watch_days: int = WATCH_WINDOW_DAYS,
    as_of: date | None = None,
) -> list[str]:
    as_of = as_of or date.today()
    ledger = load_ledger(ledger_path)
    latest = latest_row_per_dag(
        [
            row
            for row in rows
            if not str(
                row.get("prod_airflow_dag_id") or row.get("dag_id") or ""
            ).endswith("__validation")
        ]
    )
    alerts: list[str] = []

    for entry in ledger:
        promoted_at = date.fromisoformat(entry.promoted_at[:10])
        if (as_of - promoted_at).days >= watch_days:
            continue
        row = latest.get(entry.dag_id)
        if row is None:
            continue

        baseline_cost = _f(entry.baseline.get("avg_cost_usd"))
        prod_cost = _f(row.get("prod_avg_cost_usd"))
        if baseline_cost is not None and prod_cost is not None and baseline_cost > 0:
            delta_pct = (prod_cost - baseline_cost) / baseline_cost * 100.0
            if delta_pct > COST_REGRESSION_PCT:
                alerts.append(
                    f"ALERT {entry.dag_id}: cost {prod_cost:.4f} > baseline "
                    f"{baseline_cost:.4f} (+{delta_pct:.1f}%); revert spec "
                    f"{json.dumps(entry.previous_cluster_spec, sort_keys=True)}"
                )

        if _i(row.get("prod_failure_count")) > 0:
            alerts.append(
                f"ALERT {entry.dag_id}: prod failure after promotion; revert spec "
                f"{json.dumps(entry.previous_cluster_spec, sort_keys=True)}"
            )

        mem_p95 = _mem_p95_max(row, prefix="prod")
        if mem_p95 is not None and mem_p95 > MEM_WARN_THRESHOLD:
            alerts.append(
                f"ALERT {entry.dag_id}: prod memory P95 {mem_p95:.1f}% > "
                f"{MEM_WARN_THRESHOLD:.0f}%; revert spec "
                f"{json.dumps(entry.previous_cluster_spec, sort_keys=True)}"
            )

        sla_reason = _cadence_sla_breach(row, entry.baseline)
        if sla_reason:
            alerts.append(
                f"ALERT {entry.dag_id}: {sla_reason}; revert spec "
                f"{json.dumps(entry.previous_cluster_spec, sort_keys=True)}"
            )

    return alerts


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--outcomes-csv",
        type=Path,
        required=True,
        help="Trino export of datalake_databricks_health.enrich_rightsizing_outcomes",
    )
    parser.add_argument(
        "--dags-root",
        type=Path,
        default=DEFAULT_DAGS_ROOT,
        help="Root of the dags/ tree (default: repo dags/)",
    )
    parser.add_argument(
        "--quintoml-root",
        type=Path,
        default=None,
        help="QuintoML repo root for Wonka prod.yml promotion (default ~/Work/quintoml)",
    )
    parser.add_argument(
        "--report-out",
        type=Path,
        help="Write markdown promotion report to this path",
    )
    parser.add_argument(
        "--ledger",
        type=Path,
        default=DEFAULT_LEDGER_PATH,
        help="JSON ledger of promoted DAG baselines (default: scripts/rightsizing_promotion_ledger.json)",
    )
    parser.add_argument(
        "--watch",
        action="store_true",
        help="Compare ledger entries promoted in the last 7 days against fresh prod rows",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Compute decisions and report without editing cluster files or ledger",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    rows = load_outcomes_csv(args.outcomes_csv)

    if args.watch:
        for line in watch_promotions(rows, args.ledger):
            print(line)
        return 0

    decisions, _ledger = apply_promotions(
        rows,
        dags_root=args.dags_root,
        quintoml_root=args.quintoml_root,
        ledger_path=args.ledger,
        dry_run=args.dry_run,
    )
    report = render_report(decisions)
    if args.report_out:
        args.report_out.parent.mkdir(parents=True, exist_ok=True)
        args.report_out.write_text(report, encoding="utf-8")
    else:
        print(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
