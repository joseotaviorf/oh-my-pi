#!/usr/bin/env python3
"""Profile one Airflow DAG file using the production parse/serialization path.

Run this inside the Astro Runtime image so Airflow and the installed
``bietlejuice`` packages match the hosted dag-processor::

    docker run --rm \
      -e ENVIRONMENT=prod \
      -e BIETLEJUICE_PREWARM=never \
      -e AIRFLOW__CORE__LOAD_EXAMPLES=False \
      -v "$PWD/dags:/usr/local/airflow/dags:ro" \
      -v "$PWD/scripts:/workspace/scripts:ro" \
      -v "$PWD/astro/config:/usr/local/airflow/config:ro" \
      bietlejuice-airflow:local \
      bash -lc 'airflow db migrate >/tmp/migrate.log 2>&1 &&
        python /workspace/scripts/analysis/profile_dag_parse.py
        /usr/local/airflow/dags/growth/amplitude_subpartitioned/amplitude_subpartitioned_dag.py'

Use a fresh container/process per file: Airflow 2.x parses each DAG file in a
fresh forked child, so profiling several files in one interpreter would produce
unrepresentative warm-import results.
"""

from __future__ import annotations

import argparse
import cProfile
import io
import json
import pstats
import time
from collections import defaultdict
from pathlib import Path

PHASE_PATTERNS = {
    "yaml": ("yaml/", "yaml.", "file_service.py"),
    "serialization": (
        "serialized_objects.py",
        "serialized_dag.py",
        "jsonschema/",
        "param.py",
        "_keywords.py",
        "_core.py",
    ),
    "path_discovery": ("dag_packages_path_service.py", "glob.py", "posixpath.py"),
    "task_construction": (
        "task_creator",
        "/workflows/",
        "_workflow.py",
        "factory_dispatcher.py",
        "taskgroup.py",
    ),
    "validation": (
        "cerberus/",
        "dag_declaration_validator.py",
        "dag_cluster_validator.py",
    ),
    "database": ("sqlalchemy/", "airflow/utils/session.py", "airflow/settings.py"),
    "imports": ("<frozen importlib",),
}


def _phase_for(filename: str) -> str:
    normalized = filename.replace("\\", "/").lower()
    for phase, patterns in PHASE_PATTERNS.items():
        if any(pattern in normalized for pattern in patterns):
            return phase
    return "other"


def _profile_file(dag_file: Path, serialize: bool) -> dict:
    from airflow.models.dagbag import DagBag

    profiler = cProfile.Profile()
    started = time.perf_counter()
    profiler.enable()
    dag_bag = DagBag(
        dag_folder=str(dag_file),
        include_examples=False,
        safe_mode=False,
    )
    if serialize and not dag_bag.import_errors:
        from airflow.serialization.serialized_objects import SerializedDAG

        for dag in dag_bag.dags.values():
            SerializedDAG.to_dict(dag)
    profiler.disable()
    elapsed = time.perf_counter() - started

    stats = pstats.Stats(profiler)
    phase_self_s: dict[str, float] = defaultdict(float)
    for (filename, _line, _function), values in stats.stats.items():
        phase_self_s[_phase_for(filename)] += values[2]

    output = io.StringIO()
    pstats.Stats(profiler, stream=output).strip_dirs().sort_stats(
        pstats.SortKey.CUMULATIVE
    ).print_stats(30)

    return {
        "dag_file": str(dag_file),
        "elapsed_s": round(elapsed, 6),
        "dag_count": len(dag_bag.dags),
        "task_count": sum(len(dag.tasks) for dag in dag_bag.dags.values()),
        "import_errors": dag_bag.import_errors,
        "phase_self_s": {
            phase: round(seconds, 6) for phase, seconds in sorted(phase_self_s.items())
        },
        "profile_top_30": output.getvalue(),
    }


def _prepare_runtime(prewarm: bool) -> None:
    """Initialize Airflow, then optionally reproduce manager-side prewarming."""
    from airflow import settings

    settings.initialize()
    if prewarm:
        from airflow_local_settings import prewarm_bietlejuice

        prewarm_bietlejuice()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dag_file", type=Path)
    parser.add_argument(
        "--no-serialize",
        action="store_true",
        help="Profile DagBag import only, without SerializedDAG.to_dict",
    )
    parser.add_argument(
        "--cold",
        action="store_true",
        help="Skip manager-side bietlejuice prewarming (not production-like)",
    )
    parser.add_argument(
        "--json-output",
        type=Path,
        help="Also write the machine-readable result to this path",
    )
    args = parser.parse_args()

    if not args.dag_file.is_file():
        parser.error(f"DAG file does not exist: {args.dag_file}")

    _prepare_runtime(prewarm=not args.cold)
    result = _profile_file(args.dag_file, serialize=not args.no_serialize)
    print(
        json.dumps({k: v for k, v in result.items() if k != "profile_top_30"}, indent=2)
    )
    print("\nTop 30 functions by cumulative time:\n")
    print(result["profile_top_30"])
    if args.json_output:
        args.json_output.write_text(json.dumps(result, indent=2) + "\n")
    return 1 if result["import_errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
