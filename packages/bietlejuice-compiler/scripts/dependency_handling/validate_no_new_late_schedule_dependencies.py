"""
Fails when a change introduces a DAG dependency whose producer becomes available later in the
day than any pre-existing upstream of a dataset-triggered consumer, or when a cron producer's own
schedule is delayed while dataset-triggered DAGs already depend on it.

Compares merge-base vs HEAD committed ``dags/dependencies.yaml`` via ``git show``.
"""

import argparse
import os
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Set, Tuple
from zoneinfo import ZoneInfo

from croniter import croniter

BI_ETL_EJUICE_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
sys.path.append(BI_ETL_EJUICE_ROOT)

from bietlejuice.base.dependencies.bietlejuice_dependency_helper import (  # noqa: E402
    BietlejuiceDependencyHelper,
)
from bietlejuice.base.paths import DAG_PACKAGES_ROOT  # noqa: E402
from bietlejuice.ci.ci_diff_ref import (  # noqa: E402
    fetch_diff_base,
    resolve_diff_from_ref,
)
from bietlejuice.services.file_service import FileService  # noqa: E402

DEFAULT_TO_BRANCH = "HEAD"
DEPENDENCIES_PATH = "dags/dependencies.yaml"
ALLOWLIST_PATH = os.path.join(
    DAG_PACKAGES_ROOT, "dependency_exceptions", "late_schedule_acks.yaml"
)
DAG_ID_PREFIX = "bietlejuice."
LOCAL_TZ = ZoneInfo("America/Sao_Paulo")
REPRESENTATIVE_WEEKDAY = datetime(2024, 1, 1, tzinfo=LOCAL_TZ)
SEPARATOR = "=" * 70
MAX_DESCENDANTS_IN_REPORT = 20

ScheduleMap = Dict[str, dict]
Allowlist = Dict[Tuple[str, str], str]


@dataclass
class LateScheduleFinding:
    kind: str
    consumer: str
    producer: str
    producer_schedule: str
    producer_first_tick_minutes: int
    old_ready_minutes: int
    old_ready_producer: str
    descendants: List[str] = field(default_factory=list)

    @property
    def descendant_count(self) -> int:
        return len(self.descendants)


def classify_schedule(dag_schedule: Optional[dict]) -> str:
    """
    Classify a DAG schedule from its declaration ``dag`` block.

    Non-empty string ``schedule_interval`` -> cron.
    Key omitted -> dataset (waits on upstream datasets).
    YAML null -> manual (does not wait; skip as consumer).
    """
    if dag_schedule is None:
        return "dataset"
    if "schedule_interval" not in dag_schedule:
        return "dataset"
    schedule_interval = dag_schedule.get("schedule_interval")
    if schedule_interval is None:
        return "manual"
    if isinstance(schedule_interval, str) and schedule_interval.strip():
        return "cron"
    return "manual"


def first_daily_minutes(cron_expr: str) -> int:
    """Return minutes from midnight for the earliest time-of-day the cron fires.

    Scans up to a year so monthly (``0 13 15,30 * *``) and weekday-only
    expressions are not treated as midnight just because they skip 2024-01-01.
    """
    start = REPRESENTATIVE_WEEKDAY - timedelta(seconds=1)
    horizon = REPRESENTATIVE_WEEKDAY + timedelta(days=366)
    iterator = croniter(cron_expr, start)
    earliest: Optional[int] = None
    while True:
        next_tick = iterator.get_next(datetime)
        if next_tick >= horizon:
            break
        minutes = next_tick.hour * 60 + next_tick.minute
        if earliest is None or minutes < earliest:
            earliest = minutes
        if earliest == 0:
            break
    return earliest if earliest is not None else 0


def _cron_expression(schedules: ScheduleMap, dag_id: str) -> Optional[str]:
    dag_schedule = schedules.get(dag_id)
    if dag_schedule is None:
        return None
    schedule_interval = dag_schedule.get("schedule_interval")
    if isinstance(schedule_interval, str) and schedule_interval.strip():
        return schedule_interval.strip()
    return None


def flatten_upstream_dag_ids(graph: dict, consumer: str) -> Set[str]:
    dependency_list = graph.get(consumer, [])
    unique_dependencies = (
        BietlejuiceDependencyHelper.find_unique_dependencies_in_dependency_object(
            dependency_list or []
        )
    )
    return {dependency.split(":")[0] for dependency in unique_dependencies}


def _producer_availability_minutes(
    producer: str,
    graph: dict,
    schedules: ScheduleMap,
    memo: Dict[str, int],
    visiting: Optional[Set[str]] = None,
) -> int:
    if producer in memo:
        return memo[producer]

    if visiting is None:
        visiting = set()
    if producer in visiting:
        memo[producer] = 0
        return 0
    visiting.add(producer)

    schedule_kind = classify_schedule(schedules.get(producer))
    if schedule_kind == "cron":
        cron_expr = _cron_expression(schedules, producer)
        minutes = first_daily_minutes(cron_expr) if cron_expr else 0
    elif schedule_kind == "dataset":
        upstreams = flatten_upstream_dag_ids(graph, producer)
        if not upstreams:
            minutes = 0
        else:
            minutes = max(
                _producer_availability_minutes(
                    upstream, graph, schedules, memo, visiting
                )
                for upstream in upstreams
            )
    else:
        minutes = 0

    visiting.remove(producer)
    memo[producer] = minutes
    return minutes


def producer_availability_minutes(
    producer: str,
    graph: dict,
    schedules: ScheduleMap,
) -> int:
    return _producer_availability_minutes(producer, graph, schedules, {})


def _format_clock(minutes: int) -> str:
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


def _format_delta(delta_minutes: int) -> str:
    hours, minutes = divmod(delta_minutes, 60)
    return f"+{hours}h {minutes}m"


def _short_dag_name(dag_id: str) -> str:
    if dag_id.startswith(DAG_ID_PREFIX):
        return dag_id[len(DAG_ID_PREFIX) :]
    return dag_id


def _dataset_descendants(
    dag_id: str,
    graph: dict,
    schedules: ScheduleMap,
    downstreams: Optional[Dict[str, List[str]]] = None,
) -> List[str]:
    if downstreams is not None:
        candidates = downstreams.get(dag_id, [])
    else:
        candidates = BietlejuiceDependencyHelper.find_downstream_dags(
            dag_id, dependencies=graph, transitive=True
        )
    return sorted(
        descendant
        for descendant in candidates
        if classify_schedule(schedules.get(descendant)) == "dataset"
    )


def _gained_upstream_dag_ids(
    consumer: str, old_graph: dict, new_graph: dict
) -> Set[str]:
    old_upstreams = flatten_upstream_dag_ids(old_graph, consumer)
    new_upstreams = flatten_upstream_dag_ids(new_graph, consumer)
    return new_upstreams - old_upstreams


def _max_pre_existing_upstream_minutes(
    consumer: str,
    old_graph: dict,
    availability_graph: dict,
    schedules: ScheduleMap,
) -> Optional[Tuple[int, str]]:
    """Latest first-tick among the consumer's *old* upstreams.

    Returns None when the consumer had no upstreams, so a brand-new DAG or a
    first-time wait is not compared against midnight.
    """
    old_upstreams = flatten_upstream_dag_ids(old_graph, consumer)
    if not old_upstreams:
        return None
    availability_by_upstream = {
        upstream: producer_availability_minutes(upstream, availability_graph, schedules)
        for upstream in old_upstreams
    }
    latest_upstream = max(
        availability_by_upstream,
        key=lambda upstream: availability_by_upstream[upstream],
    )
    return availability_by_upstream[latest_upstream], latest_upstream


def find_late_schedule_findings(
    old_graph: dict,
    new_graph: dict,
    schedules: ScheduleMap,
    allowlist: Optional[Allowlist] = None,
    downstreams: Optional[Dict[str, List[str]]] = None,
    old_schedules: Optional[ScheduleMap] = None,
) -> List[LateScheduleFinding]:
    if allowlist is None:
        allowlist = {}
    if old_schedules is None:
        old_schedules = schedules

    findings: List[LateScheduleFinding] = []

    for consumer in sorted(new_graph):
        gained_upstreams = _gained_upstream_dag_ids(consumer, old_graph, new_graph)
        if not gained_upstreams:
            continue

        consumer_kind = classify_schedule(schedules.get(consumer))
        if consumer_kind in {"cron", "manual"}:
            continue

        old_ready = _max_pre_existing_upstream_minutes(
            consumer, old_graph, old_graph, old_schedules
        )
        if old_ready is None:
            continue
        old_ready_minutes, old_ready_producer = old_ready

        for producer in sorted(gained_upstreams):
            if allowlist.get((consumer, producer)):
                continue

            producer_minutes = producer_availability_minutes(
                producer, new_graph, schedules
            )
            if producer_minutes <= old_ready_minutes:
                continue

            cron_expr = _cron_expression(schedules, producer) or "unknown"
            findings.append(
                LateScheduleFinding(
                    kind="new_late_upstream",
                    consumer=consumer,
                    producer=producer,
                    producer_schedule=cron_expr,
                    producer_first_tick_minutes=producer_minutes,
                    old_ready_minutes=old_ready_minutes,
                    old_ready_producer=old_ready_producer,
                    descendants=_dataset_descendants(
                        consumer, new_graph, schedules, downstreams
                    ),
                )
            )

    for producer in sorted(schedules):
        old_kind = classify_schedule(old_schedules.get(producer))
        new_kind = classify_schedule(schedules.get(producer))
        if old_kind != "cron" or new_kind != "cron":
            continue

        old_cron = _cron_expression(old_schedules, producer)
        new_cron = _cron_expression(schedules, producer)
        if not old_cron or not new_cron:
            continue

        old_minutes = first_daily_minutes(old_cron)
        new_minutes = first_daily_minutes(new_cron)
        if new_minutes <= old_minutes:
            continue

        if allowlist.get((producer, producer)):
            continue

        descendants = _dataset_descendants(producer, new_graph, schedules, downstreams)
        if not descendants:
            continue

        findings.append(
            LateScheduleFinding(
                kind="delayed_producer",
                consumer=producer,
                producer=producer,
                producer_schedule=new_cron,
                producer_first_tick_minutes=new_minutes,
                old_ready_minutes=old_minutes,
                old_ready_producer=producer,
                descendants=descendants,
            )
        )

    return findings


def load_allowlist(path: str = ALLOWLIST_PATH) -> Allowlist:
    if not os.path.isfile(path):
        return {}
    payload = FileService.get_dict_from_yaml_file(path) or {}
    allowlist: Allowlist = {}
    for consumer, entries in payload.items():
        if not isinstance(entries, list):
            continue
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            producer = entry.get("producer")
            reason = entry.get("reason", "")
            if isinstance(consumer, str) and isinstance(producer, str):
                allowlist[(consumer, producer)] = str(reason)
    return allowlist


def _parse_declaration_schedules(payload: dict) -> Optional[Tuple[str, dict]]:
    dag_block = payload.get("dag")
    if not isinstance(dag_block, dict):
        return None
    dag_name = dag_block.get("name")
    if not isinstance(dag_name, str) or not dag_name.strip():
        return None
    dag_id = dag_name.strip()
    if not dag_id.startswith(DAG_ID_PREFIX):
        dag_id = f"{DAG_ID_PREFIX}{dag_id}"
    if "schedule_interval" in dag_block:
        return dag_id, {"schedule_interval": dag_block.get("schedule_interval")}
    return dag_id, {}


def load_schedules_from_declarations(dags_dir: Optional[str] = None) -> ScheduleMap:
    root = dags_dir or DAG_PACKAGES_ROOT
    schedules: ScheduleMap = {}
    for dirpath, _, filenames in os.walk(root):
        for filename in filenames:
            if not filename.endswith("_declaration.yml"):
                continue
            declaration_path = os.path.join(dirpath, filename)
            try:
                payload = FileService.get_dict_from_yaml_file(declaration_path) or {}
            except (OSError, ValueError):
                continue
            parsed = _parse_declaration_schedules(payload)
            if parsed is not None:
                dag_id, schedule = parsed
                schedules[dag_id] = schedule
    return schedules


def load_schedules_from_commit(commit: str) -> ScheduleMap:
    schedules: ScheduleMap = {}
    try:
        listing = _run(
            ["git", "ls-tree", "-r", "--name-only", commit, "dags"],
            cwd=_repository_root(),
        )
    except subprocess.CalledProcessError:
        return schedules

    import yaml

    for path in listing.stdout.splitlines():
        if not path.endswith("_declaration.yml"):
            continue
        try:
            result = _run(
                ["git", "show", f"{commit}:{path}"],
                cwd=_repository_root(),
            )
            payload = yaml.safe_load(result.stdout) or {}
        except (subprocess.CalledProcessError, ValueError):
            continue
        if not isinstance(payload, dict):
            continue
        parsed = _parse_declaration_schedules(payload)
        if parsed is not None:
            dag_id, schedule = parsed
            schedules[dag_id] = schedule
    return schedules


def load_dependencies_from_commit(commit: str) -> Optional[dict]:
    try:
        result = _run(
            ["git", "show", f"{commit}:{DEPENDENCIES_PATH}"],
            cwd=_repository_root(),
        )
    except subprocess.CalledProcessError as error:
        print(
            f"WARNING: could not read {DEPENDENCIES_PATH} at {commit}, so this "
            f"validation is being skipped. error={error.stderr}"
        )
        return None

    import yaml

    payload = yaml.safe_load(result.stdout) or {}
    if not isinstance(payload, dict):
        print(
            f"WARNING: {DEPENDENCIES_PATH} at {commit} is not a mapping, so this "
            "validation is being skipped."
        )
        return None
    return payload


def load_current_dependencies() -> dict:
    return BietlejuiceDependencyHelper.read_dependencies()


def resolve_base_commit(from_branch: str, to_branch: str) -> str:
    try:
        return _run(["git", "merge-base", from_branch, to_branch]).stdout.strip()
    except subprocess.CalledProcessError:
        print(
            f"WARNING: could not find the merge base of {from_branch} and {to_branch}, "
            f"comparing against {from_branch} directly."
        )
        return from_branch


def print_report(findings: List[LateScheduleFinding], base_commit: str) -> None:
    print(SEPARATOR)
    print("NEW LATE-SCHEDULE DAG DEPENDENCY INTRODUCED BY THIS CHANGE")
    print(SEPARATOR)
    print(
        f"This change introduces {len(findings)} late-schedule "
        f"{'issue' if len(findings) == 1 else 'issues'} not present on {base_commit}.\n"
    )

    for finding in findings:
        if finding.kind == "delayed_producer":
            print(
                f"This PR delays the cron schedule of {finding.producer}, which already "
                "has dataset-triggered downstream DAGs.\n"
            )
            print(
                f"  producer: {finding.producer}  schedule {finding.producer_schedule}  "
                f"first tick {_format_clock(finding.producer_first_tick_minutes)} "
                "America/Sao_Paulo"
            )
            print(
                f"  was:     previous first tick "
                f"{_format_clock(finding.old_ready_minutes)} ({finding.old_ready_producer})"
            )
            print(
                "  delta:   "
                f"{_format_delta(finding.producer_first_tick_minutes - finding.old_ready_minutes)} "
                "on the producer cron schedule"
            )
        else:
            print(
                "This PR is introducing a dependency whose first daily run is later than any "
                f"pre-existing dependency of {finding.consumer}.\n"
            )
            print(
                f"  new:     {finding.producer}  schedule {finding.producer_schedule}  "
                f"first tick {_format_clock(finding.producer_first_tick_minutes)} "
                "America/Sao_Paulo"
            )
            if finding.old_ready_producer:
                print(
                    f"  was:     latest pre-existing upstream first tick "
                    f"{_format_clock(finding.old_ready_minutes)} "
                    f"({finding.old_ready_producer})"
                )
            else:
                print(
                    f"  was:     latest pre-existing upstream first tick "
                    f"{_format_clock(finding.old_ready_minutes)}"
                )
            print(
                "  delta:   "
                f"{_format_delta(finding.producer_first_tick_minutes - finding.old_ready_minutes)} "
                "on the first-run-of-day dataset"
            )

        print(
            f"\n  dataset-triggered descendants that inherit this wait: "
            f"{finding.descendant_count}"
        )
        if finding.descendants:
            preview = finding.descendants[:MAX_DESCENDANTS_IN_REPORT]
            extra = finding.descendant_count - len(preview)
            names = ", ".join(_short_dag_name(descendant) for descendant in preview)
            if extra > 0:
                names = f"{names}, +{extra} more"
            print(f"    {names}")
        print("")

    print(
        "How to fix:\n"
        "  Remove the late upstream, move the consumer to cron, or add an explicit ack in\n"
        f"  {ALLOWLIST_PATH} with a clear reason when the later wait is intentional."
    )
    print(SEPARATOR)


def _repository_root() -> str:
    return _run(["git", "rev-parse", "--show-toplevel"]).stdout.strip()


def _run(
    command: List[str],
    cwd: Optional[str] = None,
    env: Optional[dict] = None,
    check: bool = True,
) -> subprocess.CompletedProcess:
    return subprocess.run(
        command, cwd=cwd, env=env, check=check, capture_output=True, text=True
    )


def _parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Fails when a change introduces a late-schedule DAG dependency not present on the "
            "merge base."
        )
    )
    parser.add_argument(
        "--from-branch",
        default=resolve_diff_from_ref(os.environ.get("CI_COMMIT_BRANCH", "")),
        help="Branch used as the comparison base (defaults to the CI target)",
    )
    parser.add_argument(
        "--to-branch",
        default=DEFAULT_TO_BRANCH,
        help=f"Branch being compared (default: {DEFAULT_TO_BRANCH})",
    )
    return parser.parse_args(argv)


def main(argv: Optional[List[str]] = None) -> int:
    args = _parse_args(argv)

    fetch_diff_base(args.from_branch)
    base_commit = resolve_base_commit(args.from_branch, args.to_branch)

    print("Looking for late-schedule DAG dependency changes...")
    old_graph = load_dependencies_from_commit(base_commit)
    if old_graph is None:
        return 0

    new_graph = load_current_dependencies()
    new_schedules = load_schedules_from_declarations()
    old_schedules = load_schedules_from_commit(base_commit)
    allowlist = load_allowlist()

    findings = find_late_schedule_findings(
        old_graph,
        new_graph,
        new_schedules,
        allowlist=allowlist,
        old_schedules=old_schedules,
    )
    if not findings:
        print(
            "No new late-schedule DAG dependencies were introduced by this change "
            f"(compared against {base_commit})."
        )
        return 0

    print_report(findings, base_commit)
    return 1


if __name__ == "__main__":
    sys.exit(main())
