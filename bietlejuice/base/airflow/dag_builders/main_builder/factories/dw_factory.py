from bietlejuice.base.airflow.dag_builders.main_builder.factories.base_factory import (
    BaseFactory,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.dw_query_workflow import (
    DWQueryWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.dw_query_delta_workflow import (
    DwQueryDeltaWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.workflow_enum import (
    WorkflowEnum,
)


class DWFactory(BaseFactory):
    """
    This class is responsible to instantiate and return
    an object of a DW Workflow (DAG), based on parameters.
    """

    _WORKFLOW_ENUM_TO_CLASS_MAPPING = {
        WorkflowEnum.QUERY_WORKFLOW: DWQueryWorkflow,
        WorkflowEnum.QUERY_DELTA_WORKFLOW: DwQueryDeltaWorkflow,
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
