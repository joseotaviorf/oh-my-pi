"""Phase 2: capture Databricks PROD baselines."""

from __future__ import annotations

import json
import logging
from dataclasses import asdict
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

from databricks_client import DatabricksAPI
from declaration import resolve_order_by_cols
from input_validation import validate_resource_name
from models import SchemaEntry, TableBaseline
from paths import REPO_ROOT
from query_builders import (
    build_count_query,
    build_describe_query,
    build_profile_query_for_schema,
    build_sample_query,
)
from profile import parse_profile_from_row, profile_from_dict, profile_to_dict
from sql_utils import detect_non_comparable_cols, load_pinned_sql, sql_hash

logger = logging.getLogger(__name__)

SKILL_DIR = Path(__file__).resolve().parent
BASELINE_ROOT = SKILL_DIR / "baseline"


def baseline_file_path(
    domain: str,
    dag_name: str,
    layer: str,
    table_name: str,
) -> Path:
    validate_resource_name(layer, "layer")
    validate_resource_name(table_name, "table")
    return BASELINE_ROOT / domain / dag_name / layer / f"{table_name}.json"


def _legacy_baseline_file_path(domain: str, dag_name: str, table_name: str) -> Path:
    return BASELINE_ROOT / domain / dag_name / f"{table_name}.json"


TableScopeKey = Tuple[str, str]  # (layer, table_name)


def baseline_lookup_key(layer: str, table_name: str) -> TableScopeKey:
    return (layer, table_name)


def format_table_label(layer: str, table_name: str) -> str:
    """Canonical ValidationResult.table label: layer/table when layer is known."""
    validate_resource_name(table_name, "table")
    if layer:
        validate_resource_name(layer, "layer")
        return f"{layer}/{table_name}"
    return table_name


def discover_tables(
    domain: str,
    dag_name: str,
    table_filter: Optional[str] = None,
    repo_root: Optional[Path] = None,
) -> List[Tuple[str, str]]:
    validate_resource_name(domain, "domain")
    validate_resource_name(dag_name, "dag")
    if table_filter is not None:
        validate_resource_name(table_filter, "table")
    root = repo_root or REPO_ROOT
    dag_path = root / "dags" / domain / dag_name / "queries"
    if not dag_path.exists():
        raise FileNotFoundError(f"DAG path not found: {dag_path}")

    tables: List[Tuple[str, str]] = []
    for layer_dir in sorted(dag_path.iterdir()):
        if not layer_dir.is_dir():
            continue
        for sql_file in sorted(layer_dir.glob("*.sql")):
            table_name = sql_file.stem
            if table_filter and table_name != table_filter:
                continue
            tables.append((table_name, layer_dir.name))
    return tables


def _schema_from_describe(parsed_rows: list[dict]) -> List[SchemaEntry]:
    schema: List[SchemaEntry] = []
    for row in parsed_rows:
        col_name = row.get("col_name") or row.get("column_name")
        data_type = row.get("data_type") or row.get("type") or "string"
        if not col_name or str(col_name).startswith("#"):
            continue
        schema.append((str(col_name), str(data_type)))
    return schema


class DatabricksBaseline:
    """Capture schema, count, and sample from Databricks PROD."""

    def __init__(
        self,
        db_api: DatabricksAPI,
        dag_name: str,
        domain: str,
        load_start_date: str,
        load_end_date: str,
        git_ref: Optional[str] = None,
        sample_limit: int = 100,
        skip_sample: bool = True,
        skip_profile: bool = False,
        table_filter: Optional[str] = None,
        layer_filter: Optional[str] = None,
        table_allowlist: Optional[Set[TableScopeKey]] = None,
        repo_root: Optional[Path] = None,
    ):
        self.db = db_api
        self.dag_name = dag_name
        self.domain = domain
        self.load_start = load_start_date
        self.load_end = load_end_date
        self.git_ref = git_ref
        self.sample_limit = sample_limit
        self.skip_sample = skip_sample
        self.skip_profile = skip_profile
        self.table_filter = table_filter
        self.layer_filter = layer_filter
        self.table_allowlist = table_allowlist
        self.repo_root = repo_root
        self.baselines: List[TableBaseline] = []

    def capture_table_baseline(self, table_name: str, layer: str) -> TableBaseline:
        pinned_sql = load_pinned_sql(
            self.domain,
            self.dag_name,
            layer,
            table_name,
            self.load_start,
            self.load_end,
            git_ref=self.git_ref,
            repo_root=self.repo_root,
        )
        baseline = TableBaseline(
            dag=self.dag_name,
            table=table_name,
            layer=layer,
            load_start_date=self.load_start,
            load_end_date=self.load_end,
            schema=[],
            count=0,
            sample_rows=0,
            sample=[],
            order_by_cols=[],
            time_pinned_functions=[
                "NOW() -> TIMESTAMP",
                "CURRENT_DATE() -> DATE (load_end_date)",
                "CURRENT_TIMESTAMP() -> TIMESTAMP",
            ],
            non_comparable_cols=[],
            sql_hash=sql_hash(pinned_sql),
            pinned_sql=pinned_sql,
        )

        logger.info("Capturing baseline: %s/%s", layer, table_name)
        try:
            describe_result = self.db.execute_sql(build_describe_query(pinned_sql))
            baseline.schema = _schema_from_describe(describe_result.row_dicts)
            baseline.order_by_cols = resolve_order_by_cols(
                table_name,
                baseline.schema,
                self.domain,
                self.dag_name,
                self.repo_root,
            )
            baseline.non_comparable_cols = detect_non_comparable_cols(
                [name for name, _ in baseline.schema]
            )
            logger.info("  Schema: %s columns", len(baseline.schema))

            if self.skip_profile:
                count_result = self.db.execute_sql(build_count_query(pinned_sql))
                if count_result.row_dicts:
                    baseline.count = int(count_result.row_dicts[0].get("cnt", 0))
                elif count_result.rows:
                    baseline.count = int(count_result.rows[0][0])
            else:
                profile_query, profile_shell = build_profile_query_for_schema(
                    pinned_sql,
                    baseline.schema,
                    checksum_skipped=set(baseline.non_comparable_cols),
                )
                profile_result = self.db.execute_sql(profile_query)
                row = profile_result.row_dicts[0] if profile_result.row_dicts else {}
                if not row and profile_result.rows:
                    row = {
                        profile_result.columns[idx]: profile_result.rows[0][idx]
                        for idx in range(len(profile_result.columns))
                    }
                baseline.count = int(row.get("cnt", 0))
                baseline.profile = parse_profile_from_row(row, profile_shell)
            logger.info("  Count: %s rows", f"{baseline.count:,}")

            if not self.skip_sample:
                sample_result = self.db.execute_sql(
                    build_sample_query(
                        pinned_sql,
                        baseline.order_by_cols,
                        self.sample_limit,
                    )
                )
                baseline.sample = sample_result.row_dicts
                baseline.sample_rows = len(baseline.sample)
                logger.info("  Sample: %s rows", baseline.sample_rows)
        except Exception as exc:
            baseline.error = str(exc)
            logger.error("  Failed: %s", exc)

        return baseline

    def run(self) -> bool:
        logger.info("=" * 70)
        logger.info("PHASE 2 - Databricks PROD Baseline Capture")
        logger.info("=" * 70)

        if not self.db.open_context():
            return False

        try:
            tables = discover_tables(
                self.domain,
                self.dag_name,
                self.table_filter,
                repo_root=self.repo_root,
            )
            if self.layer_filter is not None:
                tables = [
                    (table_name, layer)
                    for table_name, layer in tables
                    if layer == self.layer_filter
                ]
            if self.table_allowlist is not None:
                tables = [
                    (table_name, layer)
                    for table_name, layer in tables
                    if baseline_lookup_key(layer, table_name) in self.table_allowlist
                ]
            if not tables:
                logger.error("No tables discovered")
                return False

            for table_name, layer in tables:
                baseline = self.capture_table_baseline(table_name, layer)
                self.baselines.append(baseline)
        finally:
            self.db.close_context()

        baseline_dir = BASELINE_ROOT / self.domain / self.dag_name
        baseline_dir.mkdir(parents=True, exist_ok=True)

        failures = 0
        for baseline in self.baselines:
            output_file = baseline_file_path(
                self.domain,
                self.dag_name,
                baseline.layer,
                baseline.table,
            )
            output_file.parent.mkdir(parents=True, exist_ok=True)
            output_file.write_text(
                json.dumps(_baseline_to_json_dict(baseline), indent=2, default=str),
                encoding="utf-8",
            )
            logger.info("Saved baseline: %s", output_file)
            if baseline.error:
                failures += 1

        logger.info(
            "Phase 2 complete: %s baselines, %s failures",
            len(self.baselines),
            failures,
        )
        return failures == 0 and len(self.baselines) > 0


def _baseline_to_json_dict(baseline: TableBaseline) -> dict:
    payload = asdict(baseline)
    payload["profile"] = profile_to_dict(baseline.profile)
    return payload


def _baseline_from_json(data: dict) -> TableBaseline:
    schema = [tuple(item) for item in data.get("schema", [])]
    data = dict(data)
    data["schema"] = schema
    data.setdefault("load_end_date", "")
    profile_data = data.pop("profile", None)
    baseline = TableBaseline(**{k: v for k, v in data.items() if k != "profile"})
    baseline.profile = profile_from_dict(profile_data)
    return baseline


def is_baseline_valid(baseline: TableBaseline) -> bool:
    if baseline.error:
        return False
    if baseline.schema:
        return True
    return baseline.count == 0


def baseline_matches_window(
    baseline: TableBaseline,
    load_start_date: str,
    load_end_date: str,
) -> bool:
    """True when baseline counts/samples were captured for the same load window."""
    if not baseline.load_end_date:
        return False
    return (
        baseline.load_start_date == load_start_date
        and baseline.load_end_date == load_end_date
    )


def baseline_matches_sql(
    baseline: TableBaseline,
    domain: str,
    load_start_date: str,
    load_end_date: str,
    git_ref: str = "master",
    repo_root: Optional[Path] = None,
) -> bool:
    """True when the stored baseline matches pinned master SQL for the load window."""
    if not baseline.sql_hash:
        return False
    try:
        pinned_sql = load_pinned_sql(
            domain,
            baseline.dag,
            baseline.layer,
            baseline.table,
            load_start_date,
            load_end_date,
            git_ref=git_ref,
            repo_root=repo_root,
        )
    except (RuntimeError, FileNotFoundError, OSError) as exc:
        logger.warning(
            "Could not load master SQL for %s: %s",
            format_table_label(baseline.layer, baseline.table),
            exc,
        )
        return False
    return baseline.sql_hash == sql_hash(pinned_sql)


def is_baseline_fresh(
    baseline: TableBaseline,
    load_start_date: str,
    load_end_date: str,
    *,
    domain: str,
    git_ref: str = "master",
    repo_root: Optional[Path] = None,
) -> bool:
    if not is_baseline_valid(baseline):
        return False
    if not baseline_matches_window(baseline, load_start_date, load_end_date):
        return False
    return baseline_matches_sql(
        baseline,
        domain,
        load_start_date,
        load_end_date,
        git_ref=git_ref,
        repo_root=repo_root,
    )


def resolve_pin_dates(
    baseline: TableBaseline,
    load_start_date: str,
    load_end_date: str,
) -> tuple[str, str]:
    """Resolve load dates for EMR SQL pinning aligned with the Databricks baseline."""
    start = load_start_date or baseline.load_start_date
    end = load_end_date or baseline.load_end_date
    if not end:
        raise ValueError(
            f"Cannot pin SQL for {baseline.table}: load_end_date is missing "
            f"(re-run compare to capture a baseline for the current window)"
        )
    if load_start_date and load_end_date and not baseline_matches_window(
        baseline, load_start_date, load_end_date
    ):
        raise ValueError(
            f"Baseline for {baseline.table} is pinned to "
            f"{baseline.load_start_date}→{baseline.load_end_date}, "
            f"but EMR run requested {load_start_date}→{load_end_date}. "
            f"Re-capture Databricks baseline for the current window."
        )
    return start, end


def load_baseline_for_table(
    domain: str,
    dag_name: str,
    table_name: str,
    layer: str,
) -> Optional[TableBaseline]:
    baseline_file = baseline_file_path(domain, dag_name, layer, table_name)
    if baseline_file.exists():
        data = json.loads(baseline_file.read_text(encoding="utf-8"))
        return _baseline_from_json(data)

    legacy_file = _legacy_baseline_file_path(domain, dag_name, table_name)
    if not legacy_file.exists():
        return None
    baseline = _baseline_from_json(json.loads(legacy_file.read_text(encoding="utf-8")))
    if baseline.layer == layer:
        return baseline
    return None


def tables_needing_baseline(
    domain: str,
    dag_name: str,
    load_start_date: str,
    load_end_date: str,
    table_filter: Optional[str] = None,
    table_allowlist: Optional[Set[TableScopeKey]] = None,
    git_ref: str = "master",
    repo_root: Optional[Path] = None,
) -> List[Tuple[str, str]]:
    tables = discover_tables(domain, dag_name, table_filter, repo_root=repo_root)
    needing: List[Tuple[str, str]] = []
    for table_name, layer in tables:
        if (
            table_allowlist is not None
            and baseline_lookup_key(layer, table_name) not in table_allowlist
        ):
            continue
        baseline = load_baseline_for_table(domain, dag_name, table_name, layer)
        if baseline is None or not is_baseline_fresh(
            baseline,
            load_start_date,
            load_end_date,
            domain=domain,
            git_ref=git_ref,
            repo_root=repo_root,
        ):
            if baseline and is_baseline_valid(baseline):
                if not baseline_matches_window(
                    baseline, load_start_date, load_end_date
                ):
                    logger.info(
                        "  Baseline stale for %s (stored %s→%s, need %s→%s)",
                        table_name,
                        baseline.load_start_date,
                        baseline.load_end_date or "?",
                        load_start_date,
                        load_end_date,
                    )
                else:
                    logger.info(
                        "  Baseline stale for %s (master SQL changed on %s)",
                        table_name,
                        git_ref,
                    )
            needing.append((table_name, layer))
    return needing


def preflight_baselines(
    domain: str,
    dag_name: str,
    load_start_date: str,
    load_end_date: str,
    table_filter: Optional[str] = None,
    table_allowlist: Optional[Set[TableScopeKey]] = None,
    git_ref: str = "master",
    repo_root: Optional[Path] = None,
) -> Tuple[List[TableBaseline], List[str]]:
    """Return loaded baselines and names still missing/invalid/stale for the window."""
    tables = discover_tables(domain, dag_name, table_filter, repo_root=repo_root)
    baselines: List[TableBaseline] = []
    missing: List[str] = []
    for table_name, layer in tables:
        if (
            table_allowlist is not None
            and baseline_lookup_key(layer, table_name) not in table_allowlist
        ):
            continue
        baseline = load_baseline_for_table(domain, dag_name, table_name, layer)
        if baseline is None or not is_baseline_fresh(
            baseline,
            load_start_date,
            load_end_date,
            domain=domain,
            git_ref=git_ref,
            repo_root=repo_root,
        ):
            missing.append(f"{layer}/{table_name}")
        else:
            baselines.append(baseline)
    return baselines, missing


def _iter_baseline_json_files(baseline_dir: Path) -> List[Path]:
    paths = sorted(baseline_dir.glob("*/*.json"))
    for json_file in sorted(baseline_dir.glob("*.json")):
        if json_file not in paths:
            paths.append(json_file)
    return paths


def save_baseline_files(
    baseline: TableBaseline,
    domain: str,
    *,
    s3_uri: Optional[str] = None,
    emr_env: str = "prod",
) -> Path:
    """Mirror baseline to local cache and optionally upload to S3."""
    output_file = baseline_file_path(domain, baseline.dag, baseline.layer, baseline.table)
    output_file.parent.mkdir(parents=True, exist_ok=True)
    output_file.write_text(
        json.dumps(_baseline_to_json_dict(baseline), indent=2, default=str),
        encoding="utf-8",
    )
    if s3_uri:
        from emr_runner import upload_json_to_s3

        upload_json_to_s3(s3_uri, _baseline_to_json_dict(baseline), emr_env=emr_env)
    return output_file


def baseline_from_s3_payload(data: dict) -> TableBaseline:
    return _baseline_from_json(data)


def load_baselines(
    domain: str,
    dag_name: str,
    table_filter: Optional[str] = None,
    layer_filter: Optional[str] = None,
    table_allowlist: Optional[Set[TableScopeKey]] = None,
) -> List[TableBaseline]:
    baseline_dir = BASELINE_ROOT / domain / dag_name
    if not baseline_dir.exists():
        raise FileNotFoundError(f"Baseline directory not found: {baseline_dir}")

    by_key: Dict[TableScopeKey, TableBaseline] = {}
    for json_file in _iter_baseline_json_files(baseline_dir):
        table_name = json_file.stem
        if table_filter and table_name != table_filter:
            continue
        baseline = _baseline_from_json(json.loads(json_file.read_text(encoding="utf-8")))
        path_layer = "" if json_file.parent == baseline_dir else json_file.parent.name
        file_layer = path_layer or baseline.layer
        if (
            table_allowlist is not None
            and baseline_lookup_key(file_layer, table_name) not in table_allowlist
        ):
            continue
        if layer_filter and file_layer != layer_filter:
            continue
        key = baseline_lookup_key(file_layer, table_name)
        if key in by_key:
            continue
        by_key[key] = baseline
    return list(by_key.values())
