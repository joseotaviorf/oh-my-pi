from abc import abstractmethod
from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("DependencyGenerator")


class DependencyGenerator:
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
                        task["full_task_name"]
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
