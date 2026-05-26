from bietlejuice.base.airflow.dag_builders.main_builder.factories.base_factory import (
    BaseFactory,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.raw_api_ingestion_workflow import (
    RawAPIIngestionWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.raw_cdc_workflow import (
    RawCDCWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.raw_custom_ingestion_workflow import (
    RawCustomIngestionWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.raw_database_pull_delta_workflow import (
    RawDatabasePullDeltaWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.raw_database_pull_workflow import (
    RawDatabasePullWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.raw_dms_cdc_workflow import (
    RawDMSCDCWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.raw_gsheets_workflow import (
    RawGsheetsWorkflow,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.workflow_enum import (
    WorkflowEnum,
)


class RawFactory(BaseFactory):
    """
    This class is responsible to instantiate and return
    an object of a Gsheets Workflow (DAG), based on parameters.
    """

    _WORKFLOW_ENUM_TO_CLASS_MAPPING = {
        WorkflowEnum.API_INGESTION_WORKFLOW: RawAPIIngestionWorkflow,
        WorkflowEnum.GSHEETS_WORKFLOW: RawGsheetsWorkflow,
        WorkflowEnum.DATABASE_PULL_WORKFLOW: RawDatabasePullWorkflow,
        WorkflowEnum.CUSTOM_INGESTION_WORKFLOW: RawCustomIngestionWorkflow,
        WorkflowEnum.CDC_WORKFLOW: RawCDCWorkflow,
        WorkflowEnum.DATABASE_PULL_DELTA_WORKFLOW: RawDatabasePullDeltaWorkflow,
        WorkflowEnum.DMS_CDC_WORKFLOW: RawDMSCDCWorkflow,
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
