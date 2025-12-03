import os
import bietlejuice.services.dataset_service as dataset_service
import bietlejuice.base.airflow.task_creators.reprocessing_guard_task_creator as task_creator_module

from airflow.models.baseoperator import BaseOperator
from airflow.datasets import DatasetAlias
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from extra_link_plugin import DatasetTriggerOperatorLink
from typing import Union, List


class DatasetAdder:
    """
    Responsible for adding datasets ands its requirements to DAGs and tasks in Airflow.
    """

    @staticmethod
    def attach_dataset_to_task(task: BaseOperator) -> BaseOperator:
        """
        Makes the task emit a dataset event as part of its success callback.
        It also adds the button to trigger the dataset manually.
        """
        # DatasetAlias is required for us to trigger dataset events dynamically in the callback
        task.outlets.append(
            DatasetAlias(
                dataset_service.DatasetService.format_dataset_alias(
                    dag_id=task.dag_id, task_id=task.task_id
                )
            )
        )

        if task.on_success_callback is None:
            task.on_success_callback = [dataset_service.DatasetService.update_datasets]
        elif not isinstance(task.on_success_callback, list):
            task.on_success_callback = [
                task.on_success_callback,
                dataset_service.DatasetService.update_datasets,
            ]
        else:
            task.on_success_callback.append(
                dataset_service.DatasetService.update_datasets
            )

        # Shows a button to trigger the dataset manually
        task.operator_extra_links = tuple(task.operator_extra_links or ()) + (
            DatasetTriggerOperatorLink(),
        )

        return task

    @staticmethod
    def attach_reprocessing_guard(
        first_tasks_of_dag: Union[BaseOperator, List[BaseOperator]],
        dag_execution_context: DagExecutionContext = None,
    ) -> None:
        """
        Includes the reprocessing guard task in the DAG, as long as the DAG is scheduled based on dataset dependencies.
        This task ensures that the DAG does not run multiple times unnecessarily due to reprocessings.
        It will stop the DAG from running if it detects that it is a reprocessing run and the source of the reprocessing is not this DAG.
        """

        # Makes it easier to use for DAGs that are not using the DAG Builder
        if dag_execution_context is None:
            if isinstance(first_tasks_of_dag, list):
                dag = first_tasks_of_dag[0].dag
            else:
                dag = first_tasks_of_dag.dag
            env = os.environ.get("ENVIRONMENT")
            dag_execution_context = DagExecutionContext(dag, env, "", "", {}, {}, {})

        # DAG not triggered by dataset condition, so no need for reprocessing guard task.
        if dag_execution_context.dag.timetable.dataset_condition is None:
            return

        reprocessing_guard_task_creator = (
            task_creator_module.ReprocessingGuardTaskCreator(dag_execution_context)
        )
        reprocessing_guard_task = reprocessing_guard_task_creator.create_task()
        reprocessing_guard_task >> first_tasks_of_dag
