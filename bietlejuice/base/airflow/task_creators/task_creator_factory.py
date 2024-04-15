from bietlejuice.base.airflow.task_creators.data_quality_tests_task_creator import (
    DataQualityTestsTaskCreator,
)
from bietlejuice.base.airflow.task_creators.dummy_job_cluster_finished_task_creator import (
    DummyJobClusterFinishedTaskCreator,
)
from bietlejuice.base.airflow.task_creators.execute_job_cluster_task_creator import (
    ExecuteJobClusterTaskCreator,
)
from bietlejuice.base.airflow.task_creators.generate_postgres_table_metrics_task_creator import (
    GeneratePostgresTableMetricsTaskCreator,
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
from bietlejuice.base.airflow.task_creators.load_postgres_raw_task_creator import (
    LoadPostgresRawTaskCreator,
)
from bietlejuice.base.airflow.task_creators.load_mongo_raw_task_creator import (
    LoadMongoRawTaskCreator,
)
from bietlejuice.base.airflow.task_creators.load_query_task_creator import (
    LoadQueryTaskCreator,
)
from bietlejuice.base.airflow.task_creators.load_delta_table_task_creator import (
    LoadDeltaTableTaskCreator,
)
from bietlejuice.base.airflow.task_creators.optimize_delta_table_task_creator import (
    OptimizeDeltaTableTaskCreator,
)
from bietlejuice.base.airflow.task_creators.register_delta_table_task_creator import (
    RegisterDeltaTableTaskCreator,
)
from bietlejuice.base.airflow.task_creators.skip_run_task_creator import (
    SkipRunTaskCreator,
)
from bietlejuice.base.airflow.task_creators.sync_metadata_task_creator import (
    SyncMetadataTaskCreator,
)
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.airflow.enums.task_enum import TaskEnum


class TaskCreatorFactory:
    DATABASE_TYPES = ["postgres", "mongo"]

    TASK_MAPPING = {
        TaskEnum.DATA_QUALITY_TESTS: DataQualityTestsTaskCreator,
        TaskEnum.DUMMY_JOB_CLUSTER_FINISHED: DummyJobClusterFinishedTaskCreator,
        TaskEnum.EXECUTE_JOB_CLUSTER: ExecuteJobClusterTaskCreator,
        TaskEnum.GENERATE_POSTGRES_TABLE_METRICS: GeneratePostgresTableMetricsTaskCreator,
        TaskEnum.LOAD_CDC_CLEAN: LoadCDCCleanTaskCreator,
        TaskEnum.LOAD_CDC_RAW: LoadCDCRawTaskCreator,
        TaskEnum.LOAD_CDC_TRANSACTIONAL: LoadCDCTransactionalTaskCreator,
        TaskEnum.LOAD_MONGO_RAW: LoadMongoRawTaskCreator,
        TaskEnum.LOAD_POSTGRES_RAW: LoadPostgresRawTaskCreator,
        TaskEnum.LOAD_QUERY: LoadQueryTaskCreator,
        TaskEnum.LOAD_DELTA: LoadDeltaTableTaskCreator,
        TaskEnum.OPTIMIZE_DELTA_TABLE: OptimizeDeltaTableTaskCreator,
        TaskEnum.REGISTER_DELTA_TABLE: RegisterDeltaTableTaskCreator,
        TaskEnum.SKIP_RUN: SkipRunTaskCreator,
        TaskEnum.SYNC_METADATA: SyncMetadataTaskCreator,
    }

    def __init__(self, dag_execution_context: DagExecutionContext) -> None:
        self.dag_execution_context = dag_execution_context

    def __dispatch_task_creator_class(self, task: TaskEnum):
        return self.TASK_MAPPING[task]

    def get_task_creator(self, task: TaskEnum, *args, **kwargs):
        """Returns a task creator instance for the given task, configured with the DAG execution context and optional arguments."""

        task_creator_class = self.__dispatch_task_creator_class(task)
        return task_creator_class(self.dag_execution_context, *args, **kwargs)

    def get_database_task_creator(self, database_type: str, *args, **kwargs):
        """
        Returns a task creator instance of one of the currently supported database
        tasks, according to the provided database type.
        """
        if database_type not in self.DATABASE_TYPES:
            raise ValueError(
                "Database type '{}' not supported. Supported databases are: {}".format(
                    database_type, str(self.DATABASE_TYPES)
                )
            )

        database_task_enum = TaskEnum["LOAD_{}_RAW".format(database_type.upper())]

        return self.get_task_creator(database_task_enum, *args, **kwargs)
