import re
from abc import abstractmethod
from bietlejuice.base.dependencies.bietlejuice_cyclic_dependency_finder import (
    BietlejuiceCyclicDependencyFinder,
)
from bietlejuice.base.dependencies.bietlejuice_dependency_helper import (
    BietlejuiceDependencyHelper,
)
from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("DependencyGenerator")


class DependencyGenerator:
    _REGEX_TABLE_PATTERN_IN_SQL = r"(?i)(?:FROM|JOIN)\s*(\w+\.\w+)"

    @abstractmethod
    def map_tables_to_correspondent_tasks(self) -> dict:
        """
        Returns a dictionary in the following format, containing informations from all DAGs:
        {
            "<table name or database name>": {
                "dag": "<name of the dag responsible for generating the table or database>"
                "full_task_name": <full task name responsible for generating the database. Comes in the format dag_id:task_id>
            }
        }
        :return: A dictionary mapping tables to the DAGs and tasks that generate them
        :rtype: dict
        """
        raise NotImplementedError

    @abstractmethod
    def table_dependencies_from_all_dags(self) -> dict:
        """
        Map tables that are used in each DAG.
        e.g.:
        dict = {
            dag_1: [table_a, table_b, table_c],
            dag_2: [table_d, table_e, table_f]
        }
        :return: A dictionary mapping DAGs to tables used in their queries
        :rtype: dict
        """
        raise NotImplementedError

    @abstractmethod
    def treat_exceptions(self, dependencies: dict) -> dict:
        """
        Method to treat exceptions from dependencies.
        e.g.:cyclic dependency and non-static DAG depending on a static DAG

        :param dependencies: A dictionary, in which keys are DAGs and values are lists of tasks
        :type dependencies: dict
        :return: The dependency dictionary, in which keys are DAGs and values are lists of tasks
        :rtype: dict
        """
        raise NotImplementedError

    def generate_dependencies(self, dependencies_manual_modifications: dict) -> dict:
        """
        For each DAG, generate DAG dependency with other tasks, also treats
        exceptions (e.g.:cyclic dependency and non-static DAG depending on a static
        DAG) and apply manual modifications.

        :param dependencies_manual_modifications: A dictionary, in which keys are DAGs and values are dictionaries. These dictionaries
        can contain the keys "add", "remove" or "override", which are lists of tasks to be added, removed or overriden, respectively.
        :type dependencies_manual_modifications: dict
        :return: The dependency dictionary, in which keys are DAGs and values are lists of tasks
        :rtype: dict
        """
        dags_tables_dependencies = self.table_dependencies_from_all_dags()
        table_to_task_mapping = self.map_tables_to_correspondent_tasks()

        dependencies = self.replace_table_dependencies_with_tasks(
            dags_tables_dependencies, table_to_task_mapping
        )

        dependencies = self.treat_exceptions(dependencies)
        dependencies = self.apply_manual_modifications(
            dependencies, dependencies_manual_modifications
        )

        dependencies = self.sort_tasks(dependencies)
        return dependencies

    def replace_table_dependencies_with_tasks(
        self, dags_tables_dependencies: dict, table_to_task_mapping: dict
    ) -> dict:
        """
        Given a dictionary in which each key is a DAG and its values are lists of tables used in its queries,
        and another dictionary mapping tables to their corresponding DAGs and tasks,
        returns a dictionary in the structure of dependencies.yaml
        :param dags_tables_dependencies: A dictionary, in which keys are DAGs and values are lists of tables used in their queries
        :type dags_tables_dependencies: dict
        :param table_to_task_mapping: A dictionary mapping tables to their corresponding DAGs and tasks
        :type table_to_task_mapping: dict
        :return: A dictionary in the structure of dependencies.yaml
        :rtype: dict
        """
        dependencies = {}
        logger.info(
            "m=replace_table_dependencies_with_tasks, msg=generating DAG dependencies strucutre"
        )
        for dag, tables in dags_tables_dependencies.items():
            tasks = []
            for table in tables:
                database_name = table.split(".")[0]
                if table in table_to_task_mapping:
                    mapped_tasks_for_table = table_to_task_mapping[table]
                elif database_name in table_to_task_mapping:
                    mapped_tasks_for_table = table_to_task_mapping[database_name]
                else:
                    mapped_tasks_for_table = []
                tasks.extend(
                    [
                        f"{task['full_task_name']}:first-run-of-day"
                        for task in mapped_tasks_for_table
                        if task["dag"] != dag and task["full_task_name"] not in tasks
                    ]
                )
            if tasks:
                dependencies[dag] = tasks

        logger.info(
            "m=replace_table_dependencies_with_tasks, msg=dependencies strucuture generated successfully"
        )
        return dependencies

    def apply_manual_modifications(
        self, dependencies: dict, dependencies_manual_modifications: dict
    ) -> dict:
        """
        This function force manual modifications declared in
        dependencies_manual_modifications file.
        :param dependencies: A dictionary, in which keys are DAGs and values are lists of tasks
        :type dependencies: dict
        :param dependencies_manual_modifications: A dictionary, in which keys are DAGs and values are dictionaries. These dictionaries
        can contain the keys "add", "remove" or "override", which are lists of tasks to be added, removed or overriden, respectively.
        :type dependencies_manual_modifications: dict
        :return: The dependency dictionary, in which keys are DAGs and values are lists of tasks
        :rtype: dict
        """
        logger.info(
            "m=apply_manual_modifications, msg=adding, removing or overriding dependencies manually."
        )
        for dag in dependencies_manual_modifications:
            if dag not in dependencies:
                dependencies[dag] = []
            if "override" in dependencies_manual_modifications[dag]:
                dependencies[dag] = dependencies_manual_modifications[dag]["override"]
            if "add" in dependencies_manual_modifications[dag]:
                dependencies[dag].extend(
                    [
                        dependency
                        for dependency in dependencies_manual_modifications[dag]["add"]
                        if dependency not in dependencies[dag]
                    ]
                )
            if "remove" in dependencies_manual_modifications[dag]:
                dependencies[dag] = [
                    dependency
                    for dependency in dependencies[dag]
                    if dependency
                    not in dependencies_manual_modifications[dag]["remove"]
                ]
            if len(dependencies[dag]) == 0:
                dependencies.pop(dag)
        logger.info(
            "m=apply_manual_modifications, msg=manual modifications successfully applied."
        )
        return dependencies

    def sort_tasks(self, dependencies: dict) -> None:
        """
        Sort dependencies in order to make it more readable.
        :param dependencies: A dictionary, in which keys are DAGs and values are lists of tasks
        :type dependencies: dict
        :return: The dependency dictionary, in which keys are DAGs and values are lists of tasks. The tasks are sorted.
        :rtype: dict
        """
        for dependency_list in dependencies.values():
            dependency_list.sort()

        return dependencies

    def _find_all_tables_in_query_files(self, dag_query_paths: dict) -> dict:
        """
        Given a dictionary in which each key is a DAG and each value is a list of query paths,
        returns a dictionary in which each key is a DAG and each value is a table parsed from the queries.
        :param dag_query_paths: A dictionary mapping DAGs to query paths
        :type dag_query_paths: dict
        :return: A dictionary mapping DAGs to tables used in their queries
        :rtype: dict
        """
        dependencies = {}
        for dag, paths in dag_query_paths.items():
            dependencies_in_dag = set()
            for path in paths:
                dependencies_in_dag = dependencies_in_dag.union(
                    self._find_all_tables_in_query_file(path)
                )
            if dependencies_in_dag:
                dependencies[dag] = sorted(list(dependencies_in_dag))
        return dependencies

    def _find_all_tables_in_query_file(self, query_path: str) -> set:
        """ "
        Returns a set of tables inside the given query path
        :param query_path: The path to the query
        :type query_path: str
        :return: A set of tables used in the query
        :rtype: set
        """
        with open(query_path, mode="r") as query_file:
            query_content = "\n".join(query_file.readlines())
        return self._find_tables_in_query_content(query_content)

    @classmethod
    def _find_tables_in_query_content(cls, query_content: str) -> set:
        """
        Finds tables used in a SQL query.
        :param query_content: The content of the query
        :type query_content: str
        :return: A set of tables used in the query
        """
        return {
            t.lower()
            for t in re.findall(cls._REGEX_TABLE_PATTERN_IN_SQL, query_content)
            if "_raw." not in t
        }

    def _remove_cyclic_dependencies(self, dependencies: dict) -> dict:
        """
        Finds and removes circular dependencies from the dependency dictionary, returning a new one.
        :param dependencies: A dictionary, in which keys are DAGs and values are lists of tasks
        :type dependencies: dict
        :return: A dictionary, in which keys are DAGs and values are lists of tasks, without cyclic dependencies.
        :rtype: dict
        """
        logger.info("m=remove_cyclic_dependencies, msg=removing cyclic dependencies.")
        cyclic_dependencies = BietlejuiceCyclicDependencyFinder.find_all_cyclic_dependencies(
            dependencies
        )
        return BietlejuiceDependencyHelper.subtract_dependencies(
            dependencies, cyclic_dependencies
        )

    def _remove_static_dependencies_in_non_static_dags(
        self, dependencies: dict, static_dags: list
    ) -> dict:
        """
        Remove all static dependencies in non-static DAGs.
        :param dependencies: A dictionary, in which keys are DAGs and values are lists of tasks
        :type dependencies: dict
        :return: A dictionary, in which keys are DAGs and values are lists of tasks, without non-static DAGs depending on static DAGs.
        :rtype: dict
        """
        logger.info(
            "m=remove_static_dependencies_in_non_static_dags, msg=removing static dependencies in non-static DAGs."
        )
        new_dependencies = {}

        for dag, dag_dependencies in dependencies.items():
            new_dependencies[dag] = []
            is_static_dag = dag in static_dags
            for dag_dependency in dag_dependencies:
                if dag_dependency.split(":")[0] in static_dags and not is_static_dag:
                    logger.info(
                        f"msg={dag_dependency} removed from {dag}, since it is a static dependency in a non-static DAG"
                    )
                else:
                    new_dependencies[dag].append(dag_dependency)
            if len(new_dependencies[dag]) == 0:
                new_dependencies.pop(dag)
        return new_dependencies
