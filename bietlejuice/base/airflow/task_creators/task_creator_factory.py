from bietlejuice.base.airflow.task_creators.data_quality_tests_task_creator import (
    DataQualityTestsTaskCreator,
)
from bietlejuice.base.airflow.task_creators.dummy_job_cluster_finished_task_creator import (
    DummyJobClusterFinishedTaskCreator,
)
from bietlejuice.base.airflow.task_creators.execute_job_cluster_task_creator import (
    ExecuteJobClusterTaskCreator,
)
from bietlejuice.base.airflow.task_creators.load_cdc_clean_task_creator import (
    LoadCDCCleanTaskCreator,
)
from bietlejuice.base.airflow.task_creators.load_cdc_raw_task_creator import (
    LoadCDCRawTaskCreator,
)
from bietlejuice.base.airflow.task_creators.load_cdc_transactional_task_creator import (
    LoadCDCTransactionalTaskCreator,
)
from bietlejuice.base.airflow.task_creators.load_query_task_creator import (
    LoadQueryTaskCreator,
)
from bietlejuice.base.airflow.task_creators.propagate_metadata_task_creator import (
    PropagateMetadataTaskCreator,
)
from bietlejuice.base.airflow.task_creators.sync_hive_partitions_task_creator import (
    SyncHivePartitionsTaskCreator,
)
from bietlejuice.base.airflow.task_creators.sync_hive_structure_task_creator import (
    SyncHiveStructureTaskCreator,
)

from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.airflow.enums.task_enum import TaskEnum


class TaskCreatorFactory:
    TASK_MAPPING = {
        TaskEnum.DATA_QUALITY_TESTS: DataQualityTestsTaskCreator,
        TaskEnum.DUMMY_JOB_CLUSTER_FINISHED: DummyJobClusterFinishedTaskCreator,
        TaskEnum.EXECUTE_JOB_CLUSTER: ExecuteJobClusterTaskCreator,
        TaskEnum.LOAD_CDC_CLEAN: LoadCDCCleanTaskCreator,
        TaskEnum.LOAD_CDC_RAW: LoadCDCRawTaskCreator,
        TaskEnum.LOAD_CDC_TRANSACTIONAL: LoadCDCTransactionalTaskCreator,
        TaskEnum.LOAD_QUERY: LoadQueryTaskCreator,
        TaskEnum.PROPAGATE_METADATA: PropagateMetadataTaskCreator,
        TaskEnum.SYNC_HIVE_PARTITIONS: SyncHivePartitionsTaskCreator,
        TaskEnum.SYNC_HIVE_STRUCTURE: SyncHiveStructureTaskCreator,
    }

    def __init__(self, dag_execution_context: DagExecutionContext) -> None:
        self.dag_execution_context = dag_execution_context

    def get_task_creator(self, task: TaskEnum, *args, **kwargs):
        """Returns a task creator instance for the given task, configured with the DAG execution context and optional arguments."""

        task_creator_class = self.__dispatch_task_creator_class(task)
        return task_creator_class(self.dag_execution_context, *args, **kwargs)

    def __dispatch_task_creator_class(self, task: TaskEnum):
        return self.TASK_MAPPING[task]
