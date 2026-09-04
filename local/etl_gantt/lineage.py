"""Upstream Airflow job graph from inner_dependencies and dependencies.yaml."""

from __future__ import annotations

from collections import defaultdict, deque
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass, field
from pathlib import Path

import pandas as pd
import yaml

DECLARATION_GLOB = "*/*/*_declaration.yml"
INNER_DEPENDENCY_KEYS = (
    "inner_dependencies",
    "raw_inner_dependencies",
    "clean_inner_dependencies",
)
FIRST_RUN_OF_DAY_SUFFIX = "first-run-of-day"
_SKIP_DEP_SUFFIXES = frozenset({FIRST_RUN_OF_DAY_SUFFIX, "alias"})
DAG_ID_PREFIX = "bietlejuice."


@dataclass(frozen=True)
class InventoryRow:
    dag: str
    task: str
    table: str
    files_location: str = ""


@dataclass(frozen=True)
class ProducerEdge:
    """A cross-DAG dataset edge: which task, and which of its runs emits it."""

    dag: str
    task: str
    first_run_of_day: bool = False


@dataclass(frozen=True)
class Hop:
    """An upstream job: BFS depth plus which of its runs gates the consumer."""

    level: int
    first_run_of_day: bool = False


@dataclass
class JobGraph:
    """Intra-DAG table waits and cross-DAG producer tasks."""

    inner_upstream: dict[str, dict[str, tuple[str, ...]]] = field(default_factory=dict)
    dag_upstreams: dict[str, tuple[ProducerEdge, ...]] = field(default_factory=dict)
    cron_dags: frozenset[str] = frozenset()
    owners: dict[str, str] = field(default_factory=dict)
    layers: dict[str, str] = field(default_factory=dict)


def default_dags_dir() -> Path:
    return Path(__file__).resolve().parents[2] / "dags"


def parse_dependency_entry(entry: str) -> ProducerEdge | None:
    """Parse ``dag_id:task_id[:first-run-of-day]`` into a producer edge."""
    text = entry.strip()
    if not text or text.startswith("{"):
        return None
    parts = [part for part in text.split(":") if part]
    first_run_of_day = False
    if parts and parts[-1] in _SKIP_DEP_SUFFIXES:
        first_run_of_day = parts[-1] == FIRST_RUN_OF_DAY_SUFFIX
        parts = parts[:-1]
    if len(parts) != 2:
        return None
    dag_id, task_id = parts
    if not dag_id or not task_id or "." not in dag_id:
        return None
    return ProducerEdge(dag_id, task_id, first_run_of_day)


def load_cross_dag_dependencies(
    path: Path,
) -> dict[str, tuple[ProducerEdge, ...]]:
    """Map consumer DAG id to its producer dataset edges."""
    if not path.is_file():
        return {}
    payload = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    if not isinstance(payload, dict):
        return {}
    result: dict[str, tuple[ProducerEdge, ...]] = {}
    for consumer, entries in payload.items():
        if not isinstance(consumer, str) or not isinstance(entries, list):
            continue
        parsed: dict[tuple[str, str], ProducerEdge] = {}
        for entry in entries:
            if not isinstance(entry, str):
                continue
            edge = parse_dependency_entry(entry)
            if edge is None:
                continue
            key = (edge.dag, edge.task)
            previous = parsed.get(key)
            # Listed both ways: the edge that waits on a specific run rather
            # than on the day's first is the binding one.
            if previous is None or (
                previous.first_run_of_day and not edge.first_run_of_day
            ):
                parsed[key] = edge
        if parsed:
            result[consumer] = tuple(parsed.values())
    return result


def _lowercase_inner_map(
    workflow: Mapping[str, object],
) -> dict[str, tuple[str, ...]]:
    merged: dict[str, list[str]] = defaultdict(list)
    for key in INNER_DEPENDENCY_KEYS:
        block = workflow.get(key)
        if not isinstance(block, dict):
            continue
        for dependent, upstreams in block.items():
            if not isinstance(dependent, str) or not isinstance(upstreams, list):
                continue
            dest = merged[dependent.strip().lower()]
            for upstream in upstreams:
                if not isinstance(upstream, str):
                    continue
                name = upstream.strip().lower()
                if name and name not in dest:
                    dest.append(name)
    return {table: tuple(upstreams) for table, upstreams in merged.items()}


def _declaration_owner(dag_block: Mapping[str, object]) -> str:
    owner = dag_block.get("owner")
    if not isinstance(owner, str):
        return ""
    return owner.strip()


def _workflow_layer(workflow: Mapping[str, object]) -> str:
    layer = workflow.get("layer")
    if not isinstance(layer, str):
        return ""
    return layer.strip().lower()


def scan_declaration(
    path: Path,
) -> tuple[str | None, dict[str, tuple[str, ...]], str | None, str, str]:
    """Return (dag id, inner-upstream map, schedule_interval, owner, layer)."""
    empty: tuple[str | None, dict[str, tuple[str, ...]], str | None, str, str] = (
        None,
        {},
        None,
        "",
        "",
    )
    try:
        payload = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except yaml.YAMLError:
        return empty
    if not isinstance(payload, dict):
        return empty
    dag_block = payload.get("dag")
    if not isinstance(dag_block, dict):
        return empty
    name = dag_block.get("name")
    if not isinstance(name, str) or not name.strip():
        return empty
    dag_id = name.strip()
    if not dag_id.startswith(DAG_ID_PREFIX):
        dag_id = f"{DAG_ID_PREFIX}{dag_id}"
    schedule = dag_block.get("schedule_interval")
    schedule = schedule.strip() if isinstance(schedule, str) else None
    owner = _declaration_owner(dag_block)
    workflow = payload.get("workflow")
    if not isinstance(workflow, dict):
        return dag_id, {}, schedule, owner, ""
    return (
        dag_id,
        _lowercase_inner_map(workflow),
        schedule,
        owner,
        _workflow_layer(workflow),
    )


def build_job_graph(
    dags_dir: Path | None = None,
    dependencies_path: Path | None = None,
) -> JobGraph:
    root = dags_dir or default_dags_dir()
    inner_upstream: dict[str, dict[str, tuple[str, ...]]] = {}
    cron_dags: set[str] = set()
    owners: dict[str, str] = {}
    layers: dict[str, str] = {}
    for path in sorted(root.glob(DECLARATION_GLOB)):
        dag_id, inner, schedule, owner, layer = scan_declaration(path)
        if not dag_id:
            continue
        if inner:
            inner_upstream[dag_id] = inner
        if schedule:
            cron_dags.add(dag_id)
        if owner:
            owners[dag_id] = owner
        if layer:
            layers[dag_id] = layer
    yaml_path = dependencies_path or (root / "dependencies.yaml")
    return JobGraph(
        inner_upstream=inner_upstream,
        dag_upstreams=load_cross_dag_dependencies(yaml_path),
        cron_dags=frozenset(cron_dags),
        owners=owners,
        layers=layers,
    )


def frame_without_excluded_layers(
    frame: pd.DataFrame,
    layers: Mapping[str, str],
    excluded: Iterable[str],
) -> pd.DataFrame:
    """Drop upstream rows whose DAG ``workflow.layer`` is excluded; keep hop 0."""
    blocked = {
        str(item).strip().lower()
        for item in excluded
        if item is not None and str(item).strip()
    }
    if not blocked or frame.empty:
        return frame
    dag_ids = frame["id_dag"].map(lambda value: "" if value is None else str(value))
    row_layers = dag_ids.map(lambda dag_id: layers.get(dag_id, ""))
    keep_seed = frame["level"].fillna(-1).astype(int).eq(0)
    return frame.loc[keep_seed | ~row_layers.isin(blocked)].copy()


def _table_basename(name: str) -> str:
    stripped = name.strip().lower()
    if "." in stripped:
        return stripped.rsplit(".", 1)[-1]
    return stripped


def _schema_name(name: str) -> str:
    stripped = name.strip()
    if "." not in stripped:
        return ""
    return stripped.rsplit(".", 1)[0].lower()


def matching_inventory_rows(
    table: str,
    rows: Sequence[InventoryRow],
    dag_id: str | None = None,
) -> list[InventoryRow]:
    """Resolve a table FQN or basename to inventory rows."""
    needle = table.strip()
    if not needle:
        return []
    scoped = [row for row in rows if dag_id is None or row.dag == dag_id]
    exact = [row for row in scoped if row.table == needle]
    if exact:
        return exact
    bare = _table_basename(needle)
    named = [
        row
        for row in scoped
        if row.table.lower() == bare or row.table.lower().endswith("." + bare)
    ]
    schema = _schema_name(needle)
    if schema:
        located = [
            row
            for row in named
            if schema in (row.files_location or "").lower()
            or schema.replace("datalake_", "") in row.dag.lower()
        ]
        if located:
            return located
    return named


def lookup_inventory_rows(
    lookup_mode: str,
    lookup_value: str,
    inventory: Sequence[InventoryRow],
) -> list[InventoryRow]:
    """Resolve a table FQN or task id to every matching inventory producer."""
    value = lookup_value.strip()
    if not value:
        return []
    if lookup_mode == "task_id":
        return [row for row in inventory if row.task == value]
    return matching_inventory_rows(value, inventory)


def resolve_seed_jobs(
    seeds: Iterable[str],
    inventory: Sequence[InventoryRow],
) -> list[tuple[str, str]]:
    """Map seed table names to unique (dag, task) producers."""
    jobs: list[tuple[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for seed in seeds:
        for row in matching_inventory_rows(seed, inventory):
            pair = (row.dag, row.task)
            if pair in seen or not row.dag or not row.task:
                continue
            seen.add(pair)
            jobs.append(pair)
    return jobs


def _tables_for_job(
    dag_id: str,
    task_id: str,
    inventory: Sequence[InventoryRow],
) -> list[str]:
    return [row.table for row in inventory if row.dag == dag_id and row.task == task_id]


def _enqueue_job(
    dag_id: str,
    task_id: str,
    next_level: int,
    first_run_of_day: bool,
    seed_jobs: set[tuple[str, str]],
    hops: dict[tuple[str, str], Hop],
    queue: deque[tuple[str, str, int]],
) -> None:
    pair = (dag_id, task_id)
    if pair in seed_jobs:
        return
    known = hops.get(pair)
    if known is None:
        hops[pair] = Hop(level=next_level, first_run_of_day=first_run_of_day)
        queue.append((dag_id, task_id, next_level))
        return
    # Reached again through an edge that waits on a specific run: that wait
    # binds, so every run of this task stays a candidate.
    if known.first_run_of_day and not first_run_of_day:
        hops[pair] = Hop(level=known.level, first_run_of_day=False)


def upstream_job_hops(
    seeds: Iterable[str],
    inventory: Sequence[InventoryRow],
    graph: JobGraph,
    max_hop_level: int | None = None,
) -> dict[tuple[str, str], Hop]:
    """Breadth-first hop per upstream (dag, task); seeds excluded."""
    seed_jobs = resolve_seed_jobs(seeds, inventory)
    seeds_seen: set[tuple[str, str]] = set(seed_jobs)
    hops: dict[tuple[str, str], Hop] = {}
    queue: deque[tuple[str, str, int]] = deque(
        (dag_id, task_id, 0) for dag_id, task_id in seed_jobs
    )

    while queue:
        dag_id, task_id, level = queue.popleft()
        if max_hop_level is not None and level >= max_hop_level:
            continue
        next_level = level + 1
        for table in _tables_for_job(dag_id, task_id, inventory):
            for upstream in graph.inner_upstream.get(dag_id, {}).get(
                _table_basename(table),
                (),
            ):
                for row in matching_inventory_rows(upstream, inventory, dag_id=dag_id):
                    # An intra-DAG wait is on that DAG run's own task instance,
                    # never on whichever run happened to be the day's first.
                    _enqueue_job(
                        row.dag,
                        row.task,
                        next_level,
                        False,
                        seeds_seen,
                        hops,
                        queue,
                    )
        # BaseWorkflow resolves `schedule` as
        # dag_args.get("schedule_interval", dataset_dependencies), so a cron DAG
        # starts on the clock and never waits on its dependencies.yaml datasets,
        # even though the compiler still emits them into the generated stub.
        if dag_id in graph.cron_dags:
            continue
        for edge in graph.dag_upstreams.get(dag_id, ()):
            _enqueue_job(
                edge.dag,
                edge.task,
                next_level,
                edge.first_run_of_day,
                seeds_seen,
                hops,
                queue,
            )

    return hops
