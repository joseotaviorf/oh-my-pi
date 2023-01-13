import argparse
import shutil
from glob import glob
from os.path import dirname, join, basename

from dags import DAG_PACKAGES_ROOT
from scripts import SCRIPTS_PATH

DAG_PYTHON_FILE_SUFFIX = "_dag"
DAGS_TEMPLATE_FILE_PATH = join(
    SCRIPTS_PATH, "ci_cd/airflow_dag_builder/__dags_template__.py"
)

parser = argparse.ArgumentParser()
parser.add_argument("--dag_name", "-d", required=False)
args = parser.parse_args()
dag_name = args.dag_name if args.dag_name else "*"

print(f"template={DAGS_TEMPLATE_FILE_PATH}, msg=Creating DAG files from template\n")

dag_files = glob(
    pathname=f"{DAG_PACKAGES_ROOT}/**/{dag_name}_declaration.yml", recursive=True
)
for dag_file in dag_files:
    dag_package_path = dirname(dag_file)
    dag_name = basename(dag_package_path)
    dag_python_file = join(dag_package_path, f"{dag_name}{DAG_PYTHON_FILE_SUFFIX}.py")
    shutil.copy(src=DAGS_TEMPLATE_FILE_PATH, dst=dag_python_file)
    print(
        f"dag_name={dag_name}, dag_python_file={dag_python_file}, msg=Created DAG python file\n"
    )
