import argparse
from glob import glob
from os.path import basename, dirname, join

from bietlejuice.base.airflow.datasets.dataset_encoder import DatasetEncoder
from bietlejuice.base.dependencies.bietlejuice_dependency_helper import (
    BietlejuiceDependencyHelper,
)
from bietlejuice.base.dependencies.bietlejuice_redundant_dependency_finder import (
    BietlejuiceRedundantDependencyFinder,
)
from bietlejuice.services.dataset_service import DatasetService
from dags import DAG_PACKAGES_ROOT
from scripts import SCRIPTS_PATH

DAG_PYTHON_FILE_SUFFIX = "_dag"
DAGS_TEMPLATE_FILE_PATH = join(
    SCRIPTS_PATH, "ci_cd/airflow_dag_builder/__dags_template__.py"
)

parser = argparse.ArgumentParser()
parser.add_argument("--dag_name", "-d", required=False)
parser.add_argument(
    "--include-dir",
    required=False,
    help="Build only declarations whose path is under dags/<DIR>/ (e.g. luigijr).",
)
parser.add_argument(
    "--exclude-dir",
    required=False,
    help="Skip declarations whose path is under dags/<DIR>/ (e.g. luigijr). Used by the "
    "normal pipeline to keep the luigijr sandbox out of the forno/prod DAG bag.",
)
args = parser.parse_args()
dag_name = args.dag_name if args.dag_name else "*"

print("msg=Reading dependencies\n")
dependencies = BietlejuiceDependencyHelper.read_dependencies()
redundant_dependency_finder = BietlejuiceRedundantDependencyFinder(dependencies)

print(f"template={DAGS_TEMPLATE_FILE_PATH}, msg=Creating DAG files from template\n")
with open(DAGS_TEMPLATE_FILE_PATH) as f:
    template = f.read()

dag_files = glob(
    pathname=f"{DAG_PACKAGES_ROOT}/**/{dag_name}_declaration.yml", recursive=True
)

if args.include_dir:
    dag_files = [f for f in dag_files if f"/{args.include_dir}/" in f]
if args.exclude_dir:
    dag_files = [f for f in dag_files if f"/{args.exclude_dir}/" not in f]

for dag_file in dag_files:
    dag_package_path = dirname(dag_file)
    dag_name = basename(dag_package_path)
    dag_python_file = join(dag_package_path, f"{dag_name}{DAG_PYTHON_FILE_SUFFIX}.py")

    dag_id = f"bietlejuice.{dag_name}"
    dag_dependencies = dependencies.get(dag_id)
    if dag_dependencies:
        # If a DAG C depends on A and B, and B depends on A:
        # A -> B
        # A, B -> C
        # Then A is redundant for C. It would already have been triggered before B ran.
        # We need to identify these redundant dependencies. Otherwise, if we trigger a reprocessing pipeline,
        # C would be triggered twice.
        redundant_dependencies = (
            redundant_dependency_finder.find_redundant_dependencies(dag_id)
        )
    else:
        redundant_dependencies = {}

    datasets = DatasetService.get_dag_datasets_from_dependencies(
        dag_dependencies, redundant_dependencies
    )
    datasets_code = DatasetEncoder.encode_dataset_as_python_code(datasets)

    with open(dag_python_file, "w") as f:
        f.write(template.format(datasets=datasets_code))
    print(
        f"dag_name={dag_name}, dag_python_file={dag_python_file}, msg=Created DAG python file\n"
    )
