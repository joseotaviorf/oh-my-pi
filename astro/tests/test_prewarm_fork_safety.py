"""Fork-safety checks for the DAG-processor manager pre-warm."""

from __future__ import annotations

import os
import subprocess
import sys
import textwrap
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
CONFIG_DIR = REPO_ROOT / "astro/config"
# Generated + gitignored (`dags/**/*_dag.py`), so it is absent in CI steps that
# only run `uv sync`. The fork child needs a real DAG file to parse.
PARSED_DAG = REPO_ROOT / "dags/growth/reverse_supply/reverse_supply_dag.py"


@pytest.mark.skipif(not hasattr(os, "fork"), reason="pre-warm relies on POSIX fork")
@pytest.mark.skipif(
    not PARSED_DAG.is_file(),
    reason=f"{PARSED_DAG.name} not generated — run `make create-dag-files`",
)
def test_prewarm_then_fork_can_parse_real_dag(tmp_path):
    """Prewarming must not create threads/sockets that poison a fork child."""
    script = textwrap.dedent(
        f"""
        import os
        import psutil
        import sys
        import threading
        import traceback

        repo = {str(REPO_ROOT)!r}
        os.chdir(repo)
        os.environ["AIRFLOW_HOME"] = {str(tmp_path / "airflow")!r}
        os.environ["AIRFLOW__DATABASE__SQL_ALCHEMY_CONN"] = (
            "sqlite:///" + {str(tmp_path / "airflow.db")!r}
        )
        os.environ["AIRFLOW__CORE__LOAD_EXAMPLES"] = "False"
        os.environ["AIRFLOW__LOGGING__LOGGING_LEVEL"] = "ERROR"
        os.environ["BIETLEJUICE_PREWARM"] = "never"
        os.environ["ENVIRONMENT"] = "forno"
        sys.path.insert(0, repo)
        sys.path.insert(0, {str(CONFIG_DIR)!r})

        import airflow_local_settings as prewarm

        process = psutil.Process()
        before_connections = {{
            (c.fd, str(c.laddr), str(c.raddr), c.status)
            for c in process.net_connections(kind="inet")
        }}
        summary = prewarm.prewarm_bietlejuice()
        assert not summary["failed"], summary
        assert threading.active_count() == 1, threading.enumerate()
        after_connections = {{
            (c.fd, str(c.laddr), str(c.raddr), c.status)
            for c in process.net_connections(kind="inet")
        }}
        assert after_connections == before_connections

        pid = os.fork()
        if pid == 0:
            try:
                from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser import (
                    _parse_dag_declaration,
                )
                from airflow.models.dagbag import DagBag

                hits_before = _parse_dag_declaration.cache_info().hits
                dagbag = DagBag(
                    dag_folder=(
                        "dags/growth/reverse_supply/reverse_supply_dag.py"
                    ),
                    include_examples=False,
                )
                assert not dagbag.import_errors, dagbag.import_errors
                assert "bietlejuice.reverse_supply" in dagbag.dags
                assert _parse_dag_declaration.cache_info().hits > hits_before
            except BaseException:
                traceback.print_exc()
                os._exit(1)
            os._exit(0)

        _, status = os.waitpid(pid, 0)
        assert os.waitstatus_to_exitcode(status) == 0
        """
    )
    result = subprocess.run(
        [sys.executable, "-c", script],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=90,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr


def test_prewarmed_project_modules_do_not_register_atexit_handlers():
    """Keep project/plugin imports declarative before the manager forks."""
    roots = (
        REPO_ROOT / "packages/bietlejuice-core/src",
        REPO_ROOT / "packages/bietlejuice-airflow/src",
        REPO_ROOT / "packages/bietlejuice-airflow-operators/src",
        REPO_ROOT / "packages/bietlejuice-airflow-plugins/src",
    )
    offenders = []
    for root in roots:
        for source in root.rglob("*.py"):
            if "atexit.register" in source.read_text(errors="ignore"):
                offenders.append(str(source.relative_to(REPO_ROOT)))
    assert offenders == []
