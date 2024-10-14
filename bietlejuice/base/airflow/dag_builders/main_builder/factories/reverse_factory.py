from bietlejuice.base.airflow.dag_builders.main_builder.factories.base_factory import (
    BaseFactory,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.reverse_access_workflow import (
    ReverseAccessWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.workflow_enum import (
    WorkflowEnum,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.reverse_load_workflow import (
    ReverseLoadWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.reverse_load_access_workflow import (
    ReverseLoadAccessWorkflow,
)


class ReverseFactory(BaseFactory):
    """
    This class is responsible to instantiate and return
    an object of a Reverse Workflow (DAG), based on parameters.
    """

    _WORKFLOW_ENUM_TO_CLASS_MAPPING = {
        WorkflowEnum.ACCESS_WORKFLOW: ReverseAccessWorkflow,
        WorkflowEnum.LOAD_ACCESS_WORKFLOW: ReverseLoadAccessWorkflow,
        WorkflowEnum.LOAD_WORKFLOW: ReverseLoadWorkflow,
    }

    def __init__(self, dag_conf: dict, workflow_conf: dict, cluster_conf: dict):
        super().__init__()
        self.dag_conf = dag_conf
        self.workflow_conf = workflow_conf
        self.workflow_type = workflow_conf["type"]
        self.cluster_conf = cluster_conf

    def get_workflow(self) -> BaseWorkflow:
        """
        Returns an instance of a workflow class, based on the `type` parameter
        provided in the workflow component of the DAG declaration file.

        :return: BaseWorkflow
        """
        workflow_class = self._dispatch_workflow_class(WorkflowEnum(self.workflow_type))
        return workflow_class(self.dag_conf, self.workflow_conf, self.cluster_conf)
