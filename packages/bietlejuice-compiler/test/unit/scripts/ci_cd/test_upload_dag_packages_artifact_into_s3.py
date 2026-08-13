import importlib.util
import subprocess
import sys
import zipfile
from os import path

import pytest

_MODULE_PATH = path.join(
    path.dirname(__file__),
    "..",
    "..",
    "..",
    "..",
    "scripts",
    "ci_cd",
    "upload_dag_packages_artifact_into_s3.py",
)
_spec = importlib.util.spec_from_file_location(
    "upload_dag_packages_artifact_into_s3", _MODULE_PATH
)
_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_module)
write_pkg_zip = _module.write_pkg_zip


@pytest.fixture
def repo_root(tmp_path):
    """A fake repo root with the exact layout a nested spark_jobs/ package
    has on disk: no __init__.py anywhere under dags/ except at the root
    (implicit namespace packages), a root-level module (metric_config.py)
    importing a sibling from a subdirectory (framework/operations.py) --
    mirrors enrich_agent_metrics's real shape."""
    dags_dir = tmp_path / "dags" / "agents" / "some_dag" / "spark_jobs"
    framework_dir = dags_dir / "framework"
    framework_dir.mkdir(parents=True)
    (tmp_path / "dags" / "__init__.py").write_text("")
    (framework_dir / "operations.py").write_text("VALUE = 42\n")
    (dags_dir / "metric_config.py").write_text(
        "from dags.agents.some_dag.spark_jobs.framework.operations import VALUE\n"
        "CONFIG_VALUE = VALUE + 1\n"
    )
    return tmp_path


def test_pkg_zip_resolves_root_level_and_nested_absolute_imports(repo_root, tmp_path):
    """Reproduces the exact `--py-files` consumption path: add the built zip
    to sys.path in a fresh subprocess and import both the nested module and
    the root-level module that imports it, exactly as the EMR driver would."""
    dags_dir = repo_root / "dags" / "agents" / "some_dag" / "spark_jobs"
    local_files = [
        str(dags_dir / "framework" / "operations.py"),
        str(dags_dir / "metric_config.py"),
    ]
    zip_path = tmp_path / "pkg.zip"

    write_pkg_zip(str(zip_path), local_files, str(repo_root))

    result = subprocess.run(
        [
            sys.executable,
            "-c",
            "import sys; sys.path.insert(0, sys.argv[1]); "
            "from dags.agents.some_dag.spark_jobs.metric_config import CONFIG_VALUE; "
            "print(CONFIG_VALUE)",
            str(zip_path),
        ],
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "43"


def test_pkg_zip_writes_a_directory_entry_for_every_namespace_package_level(
    repo_root, tmp_path
):
    dags_dir = repo_root / "dags" / "agents" / "some_dag" / "spark_jobs"
    zip_path = tmp_path / "pkg.zip"

    write_pkg_zip(
        str(zip_path),
        [str(dags_dir / "framework" / "operations.py")],
        str(repo_root),
    )

    with zipfile.ZipFile(zip_path) as zf:
        names = set(zf.namelist())

    for namespace_dir in (
        "dags/",
        "dags/agents/",
        "dags/agents/some_dag/",
        "dags/agents/some_dag/spark_jobs/",
        "dags/agents/some_dag/spark_jobs/framework/",
    ):
        assert namespace_dir in names, f"missing namespace entry: {namespace_dir}"
