from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.base.airflow import TaskGroupMethodFactory
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.base.pipeline import LayerEnum

from copy import copy

logger = QuintoAndarLogger("BaseTaskGroup")


class BaseTaskGroup(object):
    """
    Base class for building the task group flow.
    """

    DEFAULT_EXECUTION_TIMEOUT_HOURS = 2
    TASK_GROUP_INITIAL_TASKS_DICT_KEY = "initial_tasks"
    TASK_GROUP_FINAL_TASKS_DICT_KEY = "final_tasks"
    TASK_GROUP_INDEPENDENT_TASKS_DICT_KEY = "independent_tasks"

    def __init__(
        self,
        dag,
        env,
        relative_query_path,
        spark_jobs_path,
        execution_timeout_hours=DEFAULT_EXECUTION_TIMEOUT_HOURS,
    ):
        """
        :param dag: main dag instance
        :type dag: airflow.models.DAG
        :param env: forno or prod environments
        :type env: str
        :param relative_query_path: relative query path from default queries
            path containing sql file for the table to be created
        :type relative_query_path: str
        :param spark_jobs_path: base path for spark jobs
        :type spark_jobs_path: str
        :param execution_timeout_hours: timeout in hours to be set to the tasks
        :type execution_timeout_hours: int
        """
        self.dag = dag
        self.env = env
        self.relative_query_path = relative_query_path
        self.spark_jobs_path = spark_jobs_path
        self.execution_timeout_hours = execution_timeout_hours

    def build_task_group_from_sql_files(self, layer, **kwargs):
        """
        Create a task-group for each table, based on each table's respective sql file

        :param layer: layer Enum
        :type layer: bietlejuice.jobs.composer.base.pipeline.LayerEnum member
        :return: a dict of task groups created
        :rtype: dict
        """

        schema = kwargs.get("schema")
        tree_path = kwargs.get("tree_path")
        # To avoid legacy codes who uses full / incremental on schema variable
        path_variable = schema if schema != None else tree_path

        table_names = self._get_table_names_from_sql_files(
            layer=layer, tree_path=path_variable
        )

        method = TaskGroupMethodFactory.get_method_for_build_task_group_from_sql_files(
            layer_enum=layer
        )
        task_groups = {}
        for table_name in table_names:
            params = {"table_name": table_name, **kwargs}
            task_groups[table_name] = method(self, **params)

        return task_groups

    def _get_table_names_from_sql_files(self, layer, tree_path = None):
        """
        Auxiliary method to adjust the layer and fetch table names from queries
         within the DAG's queries folder via FileService

        :param layer: the layer to get queries from its respective folder
        :type layer: bietlejuice.jobs.composer.base.pipeline.LayerEnum member
        :param tree_path: The rest of the path, used for full or incremental ingestions or specific contextual ingestions e:g crawlers listings
        :type schema: str
        :return: table_names of each query-file
        :rtype: list[str]
        """
        if layer == LayerEnum.DW_STAGING:
            layer = LayerEnum.DW

        return FileService.list_sql_files_without_extension_from_layer(
            self.relative_query_path, layer.value, tree_path
        )

    @staticmethod
    def format_tasks_boundaries(initial_tasks, final_tasks, independent_tasks=None):
        """
        Format the tasks to a dict considering the supplied hierarchy:
            initial bound and final bound of the task group, so we can apply
            the airflow tasks flows correctly.

        :param initial_tasks: the first tasks in the task group, hierarchically
        :type initial_tasks: list[airflow.models.BaseOperator]
        :param final_tasks: the last tasks in the task group, hierarchically
        :type final_tasks: list[airflow.models.BaseOperator]
        :param independent_tasks: the independent tasks in the task group, i.e., the tasks that are
        not dependencies for any other tasks or task groups
        :type independent_tasks: list[airflow.models.BaseOperator]
        :return: formatted dict with initial tasks and final tasks keys
        :rtype: dict
        """
        tasks_boundaries = {
            BaseTaskGroup.TASK_GROUP_INITIAL_TASKS_DICT_KEY: initial_tasks,
            BaseTaskGroup.TASK_GROUP_FINAL_TASKS_DICT_KEY: final_tasks,
        }

        if independent_tasks:
            tasks_boundaries[
                BaseTaskGroup.TASK_GROUP_INDEPENDENT_TASKS_DICT_KEY
            ] = independent_tasks
        return tasks_boundaries

    @staticmethod
    def first_tasks(task_group_boundaries):
        """
        Gets the initial tasks from a task group

        :param task_group_boundaries: dict of boundaries from task group
        :type task_group_boundaries: dict
        :return: initial tasks of the task group
        :rtype: list[airflow.models.BaseOperator]
        """
        return task_group_boundaries.get(
            BaseTaskGroup.TASK_GROUP_INITIAL_TASKS_DICT_KEY
        )

    @staticmethod
    def last_tasks(task_group_boundaries):
        """
        Gets the final tasks from a task group

         :param task_group_boundaries: dict of boundaries from task group
        :type task_group_boundaries: dict
        :return: final task of the task group
        :rtype: list[airflow.models.BaseOperator]
        """
        return task_group_boundaries.get(BaseTaskGroup.TASK_GROUP_FINAL_TASKS_DICT_KEY)

    @staticmethod
    def independent_tasks(task_group_boundaries):
        """
        Gets the independent tasks from a task group i.e., the tasks that are
        not dependencies for any other tasks or task groups

        :param task_group_boundaries: dict of boundaries from task group
        :type task_group_boundaries: dict
        :return: independent tasks of the task group
        :rtype: list[airflow.models.BaseOperator]
        """
        return task_group_boundaries.get(
            BaseTaskGroup.TASK_GROUP_INDEPENDENT_TASKS_DICT_KEY
        )

    @staticmethod
    def all_first_tasks(task_group_boundaries):
        """
        Gets the initial tasks of every task group as a single list.

        :param task_group_boundaries: dict of task groups containing tasks boundaries
        :type task_group_boundaries: dict
        :return: list of initial tasks of every task group
        :rtype: list[airflow.models.BaseOperator]
        """
        tasks_list = []
        for task_group in task_group_boundaries.values():
            tasks_list.extend(BaseTaskGroup.first_tasks(task_group))

        return tasks_list

    @staticmethod
    def all_last_tasks(task_group_boundaries):
        """
        Gets the last tasks of every task group as a single list.

        :param task_group_boundaries: dict of task groups containing tasks boundaries
        :type task_group_boundaries: dict
        :return: list of last tasks of every task group
        :rtype: list[airflow.models.BaseOperator]
        """
        tasks_list = []
        for task_group in task_group_boundaries.values():
            tasks_list.extend(BaseTaskGroup.last_tasks(task_group))

        return tasks_list

    @staticmethod
    def all_independent_tasks(task_group_boundaries):
        """
       Gets the independent tasks of every task group as a single list.

       :param task_group_boundaries: dict of task groups containing tasks boundaries
       :type task_group_boundaries: dict
       :return: list of independent tasks of every task group
       :rtype: list[airflow.models.BaseOperator]
       """
        tasks_list = []
        for task_group in task_group_boundaries.values():
            independent_tasks = BaseTaskGroup.independent_tasks(task_group)
            if independent_tasks:
                tasks_list.extend(independent_tasks)

        return tasks_list

    def set_inner_dag_dependencies(
        self,
        task_flow_helper,
        task_groups_boundaries: dict,
        dag_inner_dependencies: dict,
    ) -> list:
        """
        Set internal dag dependencies of task groups by
         building the DAG task-flow of one task group to another.

        :param task_flow_helper: Task Flow Helper class instance
        :type task_flow_helper: bietlejuice.jobs.composer.base.airflow.helpers.TaskFlowHelper
        :param task_groups_boundaries: dict of task groups containing tasks boundaries
        :type task_groups_boundaries: dict[str:dict[str:list[airflow.models.BaseOperator]]]
        :param dag_inner_dependencies: task name of dependant (key) and respective
            dependency (value)
        :type dag_inner_dependencies: dict[str:list[str]]
        :return: the task_group_boundaries without the inner dag dependencies task,
            and all initial and final boundaries from all the inner dag dependencies TaskGroups
        :rtype: list[
            dict[str:dict[str:list[airflow.models.BaseOperator]]],
            dict[str:list[airflow.models.BaseOperator]]
            ]
        """
        task_groups_boundaries_without_inner_dependencies = copy(task_groups_boundaries)
        all_inner_dependencies_first_tasks = []
        all_inner_dependencies_last_tasks = []

        for dependent, dependencies in dag_inner_dependencies.items():
            dependent_task_group_boundaries = task_groups_boundaries.get(dependent)
            for dependency in dependencies:
                dependency_task_group_boundaries = task_groups_boundaries.get(
                    dependency
                )

                task_flow_helper.cross_downstream_task_groups(
                    dependency_task_group_boundaries, dependent_task_group_boundaries
                )

                inner_dependencies_task_group_boundaries = self.format_tasks_boundaries(
                    initial_tasks=self.first_tasks(dependency_task_group_boundaries),
                    final_tasks=self.last_tasks(dependent_task_group_boundaries),
                )

                all_inner_dependencies_first_tasks.extend(
                    self.first_tasks(inner_dependencies_task_group_boundaries)
                )
                all_inner_dependencies_last_tasks.extend(
                    self.last_tasks(inner_dependencies_task_group_boundaries)
                )

                task_groups_boundaries_without_inner_dependencies = self._remove_task_group_from_task_groups(
                    task_group_name=dependency,
                    task_groups_boundaries=task_groups_boundaries_without_inner_dependencies,
                )

            task_groups_boundaries_without_inner_dependencies = self._remove_task_group_from_task_groups(
                task_group_name=dependent,
                task_groups_boundaries=task_groups_boundaries_without_inner_dependencies,
            )

        return [
            task_groups_boundaries_without_inner_dependencies,
            self.format_tasks_boundaries(
                initial_tasks=all_inner_dependencies_first_tasks,
                final_tasks=all_inner_dependencies_last_tasks,
            ),
        ]

    def _remove_task_group_from_task_groups(
        self, task_group_name: str, task_groups_boundaries: dict
    ) -> dict:
        """
        Make a copy of the task_groups_boundaries to not change the original var,
            and removes the specified task_group_name

        :param task_group_name: name of task_group to be removed
        :param task_groups_boundaries: dict of task groups containing tasks boundaries
        :type task_groups_boundaries: dict[str:dict[str:list[airflow.models.BaseOperator]]]
        :return: new dict with the specified key removed
        :rtype: dict[str:dict[str:list[airflow.models.BaseOperator]]]
        """
        task_groups_copy = copy(task_groups_boundaries)
        task_groups_copy.pop(task_group_name, None)
        return task_groups_copy

    def _get_load_mode(self, is_incremental: bool) -> str:
        """
        Identify the loading mode according to is_incremental flag
        """
        return "incremental" if is_incremental else "full"
