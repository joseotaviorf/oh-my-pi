from abc import ABC, abstractmethod
from typing import Dict

from airflow.datasets import BaseDataset

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.workflow_enum import (
    WorkflowEnum,
)


class BaseFactory(ABC):
    __WORKFLOW_ENUM_TO_CLASS_MAPPING = {}

    def __init__(
        self,
        dag_conf: dict,
        workflow_conf: dict,
        cluster_conf: dict,
        dataset_dependencies: BaseDataset = None,
    ):
        super().__init__()
        self.dag_conf = dag_conf
        self.workflow_conf = workflow_conf
        self.workflow_type = workflow_conf["type"]
        self.cluster_conf = cluster_conf
        self.dataset_dependencies = dataset_dependencies

    @abstractmethod
    def get_workflow(self):
        """
        Returns an instance of a workflow class, based on the `type` parameter
        provided in the workflow component of the DAG declaration file.
        """
        raise NotImplementedError()

    @property
    def _WORKFLOW_ENUM_TO_CLASS_MAPPING(self) -> Dict:
        return self.__WORKFLOW_ENUM_TO_CLASS_MAPPING

    @_WORKFLOW_ENUM_TO_CLASS_MAPPING.setter
    def _WORKFLOW_ENUM_TO_CLASS_MAPPING(self, wokflow_mapping):
        if self.__WORKFLOW_ENUM_TO_CLASS_MAPPING:
            raise RuntimeError("You can't change the workflow mapping during runtime.")
        if not isinstance(wokflow_mapping, dict):
            raise TypeError("Workflow mapping must be a dict.")
        self.__WORKFLOW_ENUM_TO_CLASS_MAPPING = wokflow_mapping

    def _dispatch_workflow_class(self, workflow_enum: WorkflowEnum):
        """
        Gets the Workflow class based on a provided workflow enum object.

        :param workflow_enum: workflow enum object used to retrieve a workflow class
        :return: BaseWorkflow
        """

        self.__validate_workflow_enum(workflow_enum)
        return self._WORKFLOW_ENUM_TO_CLASS_MAPPING[workflow_enum]

    def __validate_workflow_enum(self, workflow_enum: WorkflowEnum) -> None:
        """
        Validates that the provided workflow enum has a mapped reference of a class.

        :param workflow_enum: workflow enum object used to validate the existence of a
            respective workflow class mapped to it
        :raise: ValueError
        :return: None
        """
        available_enums = self._WORKFLOW_ENUM_TO_CLASS_MAPPING.keys()
        if workflow_enum not in available_enums:
            raise ValueError(
                f"m=__validate_workflow_class, msg=DAG Workflow {workflow_enum} does not exist, "
                "available_workflows={}".format(
                    [enum.value for enum in available_enums]
                )
            )
