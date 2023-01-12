from abc import ABC, abstractmethod
from typing import Dict

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.workflow_enum import (
    WorkflowEnum,
)


class BaseFactory(ABC):

    __WORKFLOW_ENUM_TO_CLASS_MAPPING = {}

    @abstractmethod
    def get_workflow(self) -> BaseWorkflow:
        """
        Returns an instance of a workflow class, based on the `type` parameter
        provided in the workflow component of the DAG declaration file.
        """
        raise NotImplementedError()

    @property
    @classmethod
    def _WORKFLOW_ENUM_TO_CLASS_MAPPING(cls) -> Dict:
        return cls.__WORKFLOW_ENUM_TO_CLASS_MAPPING

    @_WORKFLOW_ENUM_TO_CLASS_MAPPING.setter
    @classmethod
    def _WORKFLOW_ENUM_TO_CLASS_MAPPING(cls, wokflow_mapping):
        assert not bool(
            cls.__WORKFLOW_ENUM_TO_CLASS_MAPPING
        ), "You can't change the value of workflow mapping during runtime."
        assert isinstance(wokflow_mapping, dict), "Workflow mapping must be a dict."
        cls.__WORKFLOW_ENUM_TO_CLASS_MAPPING = wokflow_mapping

    def _dispatch_workflow_class(self, workflow_enum: WorkflowEnum) -> BaseWorkflow:
        """
        Gets the Workflow class based on a provided workflow enum object.

        :param workflow_enum: workflow enum object used to retrieve a workflow class
        :return: BaseWorkflow
        """

        self.__validate_workflow_enum(workflow_enum)
        return self.__class__._WORKFLOW_ENUM_TO_CLASS_MAPPING[workflow_enum]

    @classmethod
    def __validate_workflow_enum(cls, workflow_enum: WorkflowEnum) -> None:
        """
        Validates that the provided workflow enum has a mapped reference of a class.

        :param workflow_enum: workflow enum object used to validate the existence of a
            respective workflow class mapped to it
        :raise: ValueError
        :return: None
        """
        available_enums = cls._WORKFLOW_ENUM_TO_CLASS_MAPPING.keys()
        if workflow_enum not in available_enums:
            raise ValueError(
                f"m=__validate_workflow_class, msg=DAG Workflow does not exist, "
                "available_workflows={}".format(
                    [enum.value for enum in available_enums]
                )
            )
