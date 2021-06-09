import airflow.utils.helpers as airflow_helpers
from bietlejuice.jobs.composer.base.airflow import BaseTaskGroup


class TaskFlowHelper:
    """
    Airflow Helper to assist in the management of task flows within a DAG
    """

    @staticmethod
    def chain_task_groups_via_common_table(from_task_groups, to_task_groups):
        """
        Maps the dependencies for common tables between the task-groups.

        :param from_task_groups: dict of task groups containing tasks boundaries
            that are the dependency. They will be set as the initial
        :type from_task_groups: dict
        :param to_task_groups: dict of task groups containing tasks boundaries
            that are the dependant
        :type to_task_groups: dict
        :rtype: bool
        """

        for table_name in from_task_groups.keys():
            if not to_task_groups.get(table_name):
                raise ValueError(
                    "m=chain_task_groups_via_common_table, "
                    f"table_name={table_name}, "
                    "msg=Table does not exist in the destination task_groups."
                )

            airflow_helpers.cross_downstream(
                BaseTaskGroup.last_tasks(from_task_groups[table_name]),
                BaseTaskGroup.first_tasks(to_task_groups[table_name]),
            )

        return True
