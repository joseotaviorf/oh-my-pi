import os.path
import re
import sys
import glob

from typing import List

BI_ETL_EJUICE_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.append(BI_ETL_EJUICE_ROOT)

from bietlejuice.jobs.composer.base.paths import QUERIES_DATALAKE_PATH
from bietlejuice.jobs.composer.dags import COMPOSER_DAGS_PATH
from bietlejuice.jobs.composer.services import FileService, ConfigurationService

LAYERS = ["clean", "enrich", "dw", "raw"]

PRINT_ALL_PARSING_ERRORS = False
COMPOSER_FILES_ROOT = f"{BI_ETL_EJUICE_ROOT}/bietlejuice/jobs/composer"
DAGS_CROSS_DEPENDENCIES_FILE_NAME = "dependencies.yaml"
DAGS_CROSS_DEPENDENCIES_FILE_PATH = (
    f"{COMPOSER_DAGS_PATH}/{DAGS_CROSS_DEPENDENCIES_FILE_NAME}"
)


class CrossDAGDependenciesValidator:
    """
    Checks whether the dependent DAGs and the dependency tasks and DAGs defined
     in the DAGS_CROSS_DEPENDENCIES_FILE_NAME are valid.

    A DAG is valid if it has a declaration file.
    A task is valid if it has a SparkSQL file and the task name in dependency
     files follows the patterns.
    """

    def __init__(self) -> None:
        self.all_tables_by_dag_from_files = {}
        self.invalid_entities = {}
        self.dags_out_of_pattern = ConfigurationService().get_config(
            "dags_out_of_pattern"
        )

    @staticmethod
    def log_msg(msg, force_log=False):
        if PRINT_ALL_PARSING_ERRORS or force_log:
            print(msg + "\n")

    def register_into_invalid_list(self, dag, table=None):
        """
        Stores all invalid tables and DAGs.

        :param dag: the DAG name
        :param table: the table name
        """
        if dag in self.dags_out_of_pattern:
            return

        self.invalid_entities.setdefault(dag, [])
        if table:
            self.invalid_entities[dag].append(table)

    def extract_dag_and_table_from_file(self, file_path):
        """
        Extracts the DAG and table names from the SparkSQL query file path.

        :param file_path: the full path of table's query
        :type file_path: str
        :return: the DAG and table names
        :rtype: str, str
        """
        table_name = None
        queries_index = file_path.index("queries")
        queries_path = file_path[queries_index:]
        dag_items = queries_path.split("/")[1:]
        if dag_items[1] not in LAYERS:
            dag_name = dag_items[0]
        else:
            dag_name = self.build_dag_name(dag_items[:-1])
            layer = dag_items[1]
            table_name = f'{layer}:{dag_items[-1].replace(".sql","")}'
        return dag_name, table_name

    def load_tables_from_db_folder(self):
        """
        Loads all the table queries from db queries folder, grouped by the DAG name.

        :return: Dictionary with the tables names of each DAG
        :rtype: dict[str:list()]
        """
        all_query_files = FileService.list_all_files_recursively(QUERIES_DATALAKE_PATH)
        for file_path in all_query_files:
            dag_name, table_name = self.extract_dag_and_table_from_file(
                file_path=file_path
            )
            if not table_name:
                self.register_into_invalid_list(dag_name)
                self.log_msg(
                    msg=f"dag={dag_name}, query_file={file_path}, msg=File skipped. Error parsing file path because the query path is non-standard."
                )
                continue

            self.all_tables_by_dag_from_files.setdefault(dag_name, [])
            self.all_tables_by_dag_from_files[dag_name].append(table_name)

    @staticmethod
    def extract_dependent_dags_from_dependencies(dependencies_dict):
        """
        Given the dependencies dictionary, it extracts the dependent DAGs names.

        :param dependencies_dict: the DAGs dependencies
        :type dependencies_dict: dict[str:list()]
        :return: the DAGs names
        :rtype: list
        """
        dependent_dags = []
        for dag_name in dependencies_dict.keys():
            match = re.search("bietlejuice\.(\w*)", dag_name)
            dependent_dags.append(match.group(1))
        return dependent_dags

    @staticmethod
    def is_task(dependency_name):
        """
        Verifies if the dependency is a task or an entire DAG.
        For tasks we utilize this syntax: dag_name:task_name

        :type dependency_name: str
        :rtype: bool
        """
        return dependency_name.find(":") != -1

    def _get_table_name_from_redshift_task(self, dag_name, layer, redshift_task):
        """
        Clean the redshift task in order to retrieve the table name being loaded

        :type dag_name: str
        :type layer: str
        :type redshift_task: str
        :return: str
        """
        dag_context = dag_name.replace(f"{layer}_", "")
        table_name = redshift_task.replace("-", "_").replace(f"{dag_context}_", "")
        return table_name
    
    def _extract_dag_and_table_from_redshift_task(self, task_name):
        """
        Parses the DAG and table name from load into redshift tasks

        :type task_name: str
        :return: str, str
        """
        match = re.search("bietlejuice\.(.*):load-(public)?(.*)-into-redshift", task_name)

        if not match:
            match_dag_name = re.search("bietlejuice\.(\w*):(.*)", task_name)
            dag_name = match_dag_name.group(1)
            return dag_name, None

        layer = "dw"
        dag_name = match.group(1)
        redshift_task = match.group(3)

        table_name = self._get_table_name_from_redshift_task(dag_name, layer, redshift_task)
        table_name = f"{layer}:{table_name}"

        return dag_name, table_name

    def extract_dag_and_table_from_task_name(self, task_name):
        """
        Parses the DAG and table name from task name

        :type task_name: str
        :return: str, str
        """
        if task_name.endswith("-into-redshift"):
            return self._extract_dag_and_table_from_redshift_task(task_name)

        if task_name.endswith("-external-table"):
            task_name_pattern = "bietlejuice\.(.*):create-(enrich|raw|clean|dw)*-(.*)-external-table"
        else:
            task_name_pattern = "bietlejuice\.(.*):load-(enrich|raw|clean|dw)*-(.*)"

        match = re.search(task_name_pattern, task_name)
        if match is None:
            match_dag_name = re.search("bietlejuice\.(\w*):(.*)", task_name)
            dag_name = match_dag_name.group(1)
            return dag_name, None

        dag_name = match.group(1)

        match_layer = re.search("(dw|enrich|clean|raw)", task_name)
        if match_layer is None:
            return dag_name, None

        layer = match_layer.group(1)
        table_name = match.group(3).replace("-", "_")
        table_name = f"{layer}:{table_name}"
        return dag_name, table_name

    def extract_dependency_dags_and_tables_from_dependencies(self, dependencies):
        """
        Extracts the table names or DAG names from the dependencies, according to
         the dependency type.

        :type dependencies: dict[str:list()]
        :return: a list of DAGs and a dictionary with the tables grouped by DAG
        :rtype: list, dict[str:list()]
        """
        dags_without_tasks_in_dependencies_file = []
        tables_by_dag = {}
        for dependency_group in dependencies.values():
            for dependency_name in dependency_group:

                if self.is_task(dependency_name):
                    dag_name, table_name = self.extract_dag_and_table_from_task_name(
                        dependency_name
                    )
                    if table_name is None:
                        self.register_into_invalid_list(dag_name)
                        self.log_msg(
                            f"dag={dag_name}, dependency={dependency_name}, msg=Error parsing the dependency task from dependency.yaml. The task is non-standard and the DAG is not using the TaskGroups builder."
                        )
                        continue

                    tables_by_dag.setdefault(dag_name, [])
                    tables_by_dag[dag_name].append(table_name)
                else:  # the dependency is on a DAG
                    match_dag_name = re.search("bietlejuice\.(.*)", dependency_name)
                    dag_name = match_dag_name.group(1)
                    dags_without_tasks_in_dependencies_file.append(dag_name)
        return dags_without_tasks_in_dependencies_file, tables_by_dag

    def get_tables_from_dependency_file(self):
        """
        Identifies the tables and DAGs registered in the dependencies file.

        :return: a list of DAGs and a dictionary with the tables grouped by DAG
        :rtype: list, dict[str:list()]
        """
        dependencies = FileService.get_dict_from_yaml_file(
            DAGS_CROSS_DEPENDENCIES_FILE_PATH
        )

        dags_without_tasks_in_dependencies_file = (
            self.extract_dependent_dags_from_dependencies(dependencies)
        )

        dags, tables_by_dag = self.extract_dependency_dags_and_tables_from_dependencies(
            dependencies
        )
        dags_without_tasks_in_dependencies_file.extend(dags)

        return dags_without_tasks_in_dependencies_file, tables_by_dag

    @staticmethod
    def build_dag_name(dag_items: List[str]) -> str:
        """
        Extracts the DAG name of the query file path.

        :param dag_items: An array that contains the path of the dag splitted e.g [risk_and_mortgage,clean, xpto.sql]
        :return: the name of the dag
        """
        dag_name = dag_items[0]
        # This validation gets all folder who has legacy pattern using full and incremental and will get the dag name from subfolders
        if len(dag_items) >= 3 and dag_items[2] not in ("full", "incremental"):
            dag_name = dag_items[-1]
        return dag_name

    @staticmethod
    def dag_file_exists(dag_name):
        """
        Verifies if the DAG has a declaration file in the DAGs' path.

        :param dag_name: the dag name
        :type dag_name: str
        :rtype: bool
        """
        dag_file = f"{COMPOSER_FILES_ROOT}/dags/**/{dag_name}.py"
        validate_dag_file = glob.glob(dag_file, recursive=True)
        return len(validate_dag_file) != 0

    def table_query_exists(self, dag, table):
        """
        Verifies if the table has a respective query file.

        :param dag: the DAG name
        :type dag: str
        :param table: the table name
        :type table: str
        :rtype: bool
        """
        return (
            dag in self.all_tables_by_dag_from_files
            and table in self.all_tables_by_dag_from_files[dag]
        )

    def validate_dags(self, dags):
        """
        Verifies if the DAG is valid and in opposite case register it on the
        invalid DAGs list.

        :param dags: the DAGs names
        :type dags: list[str]
        """
        for dag in dags:
            if not self.dag_file_exists(dag):
                self.register_into_invalid_list(dag)

    def validate_tables(self, tables_by_dag):
        """
        Check whether each task from dependencies file has a respective query.

        :param tables_by_dag: the tables name (extracted from task name), grouped by DAG
        :type tables_by_dag: dict
        """
        for dag in tables_by_dag:
            if not self.dag_file_exists(dag):
                self.register_into_invalid_list(dag)
            else:
                for table in tables_by_dag[dag]:
                    if not self.table_query_exists(dag, table):
                        self.register_into_invalid_list(dag, table)

    def validate(self):
        """
        Main validation method.

        :return: 1 for error or 0 for success
        :rtype: int
        """
        self.log_msg(
            msg=f"msg=Validating dependencies from {DAGS_CROSS_DEPENDENCIES_FILE_NAME}",
            force_log=True,
        )
        self.log_msg(
            msg=f"non_standard_dags={self.dags_out_of_pattern}, msg=Ignoring out-of-pattern DAGs.",
            force_log=True,
        )

        self.load_tables_from_db_folder()
        (
            dags_without_tasks_in_file,
            tables_in_file,
        ) = self.get_tables_from_dependency_file()

        self.validate_dags(dags_without_tasks_in_file)
        self.validate_tables(tables_in_file)

        msg = "msg=All the dependencies are valid."
        status = 0
        if self.invalid_entities:
            msg = f"invalid_dags_or_tables={self.invalid_entities}, msg=These DAGs or tables set in the dependency file are invalid."
            status = 1

        self.log_msg(msg=f"msg={msg}", force_log=True)
        return status


dependencies_validator = CrossDAGDependenciesValidator()
validation_status = dependencies_validator.validate()
exit(validation_status)
