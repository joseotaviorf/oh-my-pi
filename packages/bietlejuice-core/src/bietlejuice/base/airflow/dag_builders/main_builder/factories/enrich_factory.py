from bietlejuice.base.airflow.dag_builders.main_builder.factories.base_factory import (
    BaseFactory,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.enrich_query_delta_workflow import (
    EnrichQueryDeltaWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.enrich_query_workflow import (
    EnrichQueryWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.query_view_workflow import (
    QueryViewWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.workflow_enum import (
    WorkflowEnum,
)


class EnrichFactory(BaseFactory):
    """
    This class is responsible to instantiate and return
    an object of a DW Workflow (DAG), based on parameters.
    """

    _WORKFLOW_ENUM_TO_CLASS_MAPPING = {
        WorkflowEnum.QUERY_WORKFLOW: EnrichQueryWorkflow,
        WorkflowEnum.QUERY_DELTA_WORKFLOW: EnrichQueryDeltaWorkflow,
        WorkflowEnum.QUERY_VIEW_WORKFLOW: QueryViewWorkflow,
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
            **(self._workflow_validation_kwargs() or {}),
        )
