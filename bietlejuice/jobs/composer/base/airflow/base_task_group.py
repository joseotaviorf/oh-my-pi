from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.base.airflow import TaskGroupMethodFactory
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.base.pipeline import LayerEnum

logger = QuintoAndarLogger("BaseTaskGroup")


class BaseTaskGroup(object):
    """
    Base class for building the task group flow.
    """

    DEFAULT_EXECUTION_TIMEOUT_HOURS = 2
    TASK_GROUP_INITIAL_TASKS_DICT_KEY = "initial_tasks"
    TASK_GROUP_FINAL_TASKS_DICT_KEY = "final_tasks"

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
        table_names = self._get_table_names_from_sql_files(
            layer=layer, schema=kwargs.get("schema")
        )

        method = TaskGroupMethodFactory.get_method_for_build_task_group_from_sql_files(
            layer_enum=layer
        )
        task_groups = {}
        for table_name in table_names:
            params = {"table_name": table_name, **kwargs}
            task_groups[table_name] = method(self, **params)

        return task_groups

    def _get_table_names_from_sql_files(self, layer, schema=None):
        """
        Auxiliary method to adjust the layer and fetch table names from queries
         within the DAG's queries folder via FileService

        :param layer: the layer to get queries from its respective folder
        :type layer: bietlejuice.jobs.composer.base.pipeline.LayerEnum member
        :param schema: schema name of the folder which the queries are inside
        :type schema: str
        :return: table_names of each query-file
        :rtype: list[str]
        """
        if layer == LayerEnum.DW_STAGING:
            layer = LayerEnum.DW

        return FileService.list_sql_files_without_extension_from_layer(
            self.relative_query_path, layer.value, schema
        )

    @staticmethod
    def format_tasks_boundaries(initial_tasks, final_tasks):
        """
        Format the tasks to a dict considering the supplied hierarchy:
            initial bound and final bound of the task group, so we can apply
            the airflow tasks flows correctly.

        :param initial_tasks: the first tasks in the task group, hierarchically
        :type initial_tasks: list[airflow.models.BaseOperator]
        :param final_tasks: the last tasks in the task group, hierarchically
        :type final_tasks: list[airflow.models.BaseOperator]
        :return: formatted dict with initial tasks and final tasks keys
        :rtype: dict
        """

        return {
            BaseTaskGroup.TASK_GROUP_INITIAL_TASKS_DICT_KEY: initial_tasks,
            BaseTaskGroup.TASK_GROUP_FINAL_TASKS_DICT_KEY: final_tasks,
        }

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
