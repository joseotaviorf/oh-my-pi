from bietlejuice.base.airflow.dag_builders.main_builder.factories.base_factory import (
    BaseFactory,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.qube_dimension_workflow import (
    QubeDimensionWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.qube_measure_workflow import (
    QubeMeasureWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.qube_metric_workflow import (
    QubeMetricWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.workflow_enum import (
    WorkflowEnum,
)


class QubeFactory(BaseFactory):
    """
    This class is responsible to instantiate and return
    an object of a QUBE Workflow (DAG), based on parameters.
    """

    _WORKFLOW_ENUM_TO_CLASS_MAPPING = {
        WorkflowEnum.QUBE_DIMENSION_WORKFLOW: QubeDimensionWorkflow,
        WorkflowEnum.QUBE_MEASURE_WORKFLOW: QubeMeasureWorkflow,
        WorkflowEnum.QUBE_METRIC_WORKFLOW: QubeMetricWorkflow,
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
