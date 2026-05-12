from bietlejuice.base.airflow.dag_builders.main_builder.factories.base_factory import (
    BaseFactory,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.core_model_workflow import (
    CoreModelWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.core_query_delta_workflow import (
    CoreQueryDeltaWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.workflow_enum import (
    WorkflowEnum,
)


class CoreFactory(BaseFactory):
    """
    This class is responsible to instantiate and return
    an object of a Core Workflow (DAG), based on parameters.
    """

    _WORKFLOW_ENUM_TO_CLASS_MAPPING = {
        WorkflowEnum.CORE_MODEL_WORKFLOW: CoreModelWorkflow,
        WorkflowEnum.QUERY_DELTA_WORKFLOW: CoreQueryDeltaWorkflow,
    }

    def get_workflow(self) -> BaseWorkflow:
        """
        Returns an instance of a workflow class, based on the `type` parameter
        provided in the workflow component of the DAG declaration file.

        :return: BaseWorkflow
        """
        workflow_class = self._dispatch_workflow_class(WorkflowEnum(self.workflow_type))
        return workflow_class(
            self.dag_conf,
            self.workflow_conf,
            self.cluster_conf,
            self.dataset_dependencies,
        )
