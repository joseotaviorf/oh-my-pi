from abc import ABC, abstractmethod

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)


class AbstractFactory(ABC):
    @abstractmethod
    def get_workflow(self) -> BaseWorkflow:
        """
        Returns the Workflow class based on the parameter `workflow type` defined in the DAG declaration file.
        """
        raise NotImplementedError()
