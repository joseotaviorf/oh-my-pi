from abc import ABC, abstractmethod

from airflow.models.baseoperator import BaseOperator

import bietlejuice.base.airflow.datasets.dataset_adder as dataset_adder
from bietlejuice.base.airflow.enums.storage_format_enum import StorageFormatEnum
from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes


class LoadTaskCreator(BaseTaskCreator, ABC):
    """Base class for creating tasks that load data"""

    def __init__(
        self,
        dag_execution_context,
        produce_datasets: bool = True,
        storage_format: StorageFormatEnum = None,
    ):
        super().__init__(dag_execution_context)
        self.produce_datasets = produce_datasets
        self.storage_format = storage_format

    @abstractmethod
    def _create_base_load_task(self, table_attributes: TableAttributes) -> BaseOperator:
        """
        Each load task creator must implement this method to create its specific load task.
        The resulting task will then be modified to attach the necessary changes for all load tasks, like
        attaching the dataset to the task or applying common parameters.
        """

    def create_task(self, table_attributes: TableAttributes) -> BaseOperator:
        produce_datasets = self.produce_datasets and not getattr(
            self.dag_execution_context, "is_validation", False
        )
        task = self._create_base_load_task(table_attributes)
        if produce_datasets:
            dataset_adder.DatasetAdder.attach_dataset_to_task(task)
            # Used as metadata to track which table this task is responsible for
            task.params.update(
                {
                    "schema": table_attributes.schema,
                    "table_name": table_attributes.table_name,
                    "layer": table_attributes.layer.value,
                    "bucket": self.dag_execution_context.bucket,
                    "storage_format": (
                        self.storage_format.value if self.storage_format else None
                    ),
                    **(
                        {"transformation_grade": table_attributes.transformation_grade}
                        if table_attributes.transformation_grade
                        else {}
                    ),
                    "criticality": table_attributes.criticality,
                    "owner": table_attributes.owner,
                }
            )
        return task
