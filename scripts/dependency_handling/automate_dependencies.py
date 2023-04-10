import yaml

from airflow.models import DagBag
from bietlejuice.base.dependencies.dag_bag_dependency_generator import (
    DagBagDependencyGenerator,
)

from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.dag_bag_service import DagBagService

config_service = ConfigurationService()
databricks_bietlejuice_repo_path = config_service.get_config(
    "databricks_bietlejuice_repo_path"
)
BASE_SPARK_JOBS_PATH = f"{databricks_bietlejuice_repo_path}/spark_jobs/base/".replace('//', '/')
LOCAL_ENV_DAGS_FOLDER = '/bi-etl-ejuice/local/bietlejuice/dags/dags'
OUTPUT_FILE_TEMPLATE = '/bi-etl-ejuice/local/bietlejuice/scripts/dependency_handling/{}.yaml'
EXCEPTIONS_FILE_PATH = '/bi-etl-ejuice/local/bietlejuice/scripts/dependency_handling/dependency_exceptions.yaml'


def main():
    dag_bag = DagBag(dag_folder='/bi-etl-ejuice/local/bietlejuice/dags/dags', store_serialized_dags=False, include_examples=False)
    dag_bag_service = DagBagService(dag_bag, collect_from_database=False)

    dag_bag_dependency_generator = DagBagDependencyGenerator(
        dag_bag_service, BASE_SPARK_JOBS_PATH, LOCAL_ENV_DAGS_FOLDER
    )

    dependency_exception = get_exception_file(EXCEPTIONS_FILE_PATH)

    dependencies = dag_bag_dependency_generator.generate_dependencies(
        dependency_exception
    )
    write_to_yml(dependencies, "dependencies_with_tasks")


def write_to_yml(table_dependencies: dict, file_name: str):
    with open(OUTPUT_FILE_TEMPLATE.format(file_name), mode="w+") as file_stream:
        yaml.dump(table_dependencies, file_stream, explicit_start=True)


def get_exception_file(exceptions_file_path: str):
    try:
        with open(exceptions_file_path) as dependency_exception_file:
            dependency_exceptions = yaml.safe_load(dependency_exception_file)
            return dependency_exceptions
    except FileNotFoundError as e:
        print(f"msg=Exceptions file not found, no manual changes will be applied to the output. error={e}")
        return {}


if __name__ == "__main__":
    main()
