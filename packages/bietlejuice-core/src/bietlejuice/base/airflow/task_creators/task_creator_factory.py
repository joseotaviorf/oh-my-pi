from bietlejuice.base.airflow.enums.task_enum import TaskEnum
from bietlejuice.base.airflow.task_creators.add_default_row_task_creator import (
    AddDefaultRowTaskCreator,
)
from bietlejuice.base.airflow.task_creators.build_qube_dimension_task_creator import (
    BuildQubeDimensionTaskCreator,
)
from bietlejuice.base.airflow.task_creators.build_qube_measure_task_creator import (
    BuildQubeMeasureTaskCreator,
)
from bietlejuice.base.airflow.task_creators.build_qube_metric_task_creator import (
    BuildQubeMetricTaskCreator,
)
from bietlejuice.base.airflow.task_creators.create_query_view_task_creator import (
    CreateQueryViewTaskCreator,
)
from bietlejuice.base.airflow.task_creators.dag_execution_context import (
    DagExecutionContext,
)
from bietlejuice.base.airflow.task_creators.data_quality_tests_task_creator import (
    DataQualityTestsTaskCreator,
)
from bietlejuice.base.airflow.task_creators.dummy_job_cluster_finished_task_creator import (
    DummyJobClusterFinishedTaskCreator,
)
from bietlejuice.base.airflow.task_creators.execute_job_cluster_task_creator import (
    ExecuteJobClusterTaskCreator,
)
from bietlejuice.base.airflow.task_creators.generate_database_table_metrics_task_creator import (
    GenerateDatabaseTableMetricsTaskCreator,
)
from bietlejuice.base.airflow.task_creators.load_api_raw_task_creator import (
    LoadAPIRawTaskCreator,
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
from bietlejuice.base.airflow.task_creators.load_cdf_to_datazord_task_creator import (
    LoadCDFtoDatazordTaskCreator,
)
from bietlejuice.base.airflow.task_creators.load_custom_task_creator import (
    LoadCustomTaskCreator,
)
from bietlejuice.base.airflow.task_creators.load_delta_table_task_creator import (
    LoadDeltaTableTaskCreator,
)
from bietlejuice.base.airflow.task_creators.load_dms_cdc_clean_task_creator import (
    LoadDMSCDCCleanTaskCreator,
)
from bietlejuice.base.airflow.task_creators.load_dms_cdc_raw_task_creator import (
    LoadDMSCDCRawTaskCreator,
)
from bietlejuice.base.airflow.task_creators.load_mongo_raw_task_creator import (
    LoadMongoRawTaskCreator,
)
from bietlejuice.base.airflow.task_creators.load_postgres_raw_task_creator import (
    LoadPostgresRawTaskCreator,
)
from bietlejuice.base.airflow.task_creators.load_query_task_creator import (
    LoadQueryTaskCreator,
)
from bietlejuice.base.airflow.task_creators.load_wonka_task_creator import (
    LoadWonkaTaskCreator,
)
from bietlejuice.base.airflow.task_creators.optimize_delta_table_task_creator import (
    OptimizeDeltaTableTaskCreator,
)
from bietlejuice.base.airflow.task_creators.qube_register_delta_table_task_creator import (
    QubeRegisterDeltaTableTaskCreator,
)
from bietlejuice.base.airflow.task_creators.register_delta_table_task_creator import (
    RegisterDeltaTableTaskCreator,
)
from bietlejuice.base.airflow.task_creators.reprocessing_guard_task_creator import (
    ReprocessingGuardTaskCreator,
)
from bietlejuice.base.airflow.task_creators.skip_run_task_creator import (
    SkipRunTaskCreator,
)
from bietlejuice.base.airflow.task_creators.sync_metadata_task_creator import (
    SyncMetadataTaskCreator,
)


class TaskCreatorFactory:
    DATABASE_TYPES = ["postgres", "mongo"]

    TASK_MAPPING = {
        TaskEnum.ADD_DEFAULT_ROW: AddDefaultRowTaskCreator,
        TaskEnum.DATA_QUALITY_TESTS: DataQualityTestsTaskCreator,
        TaskEnum.DUMMY_JOB_CLUSTER_FINISHED: DummyJobClusterFinishedTaskCreator,
        TaskEnum.EXECUTE_JOB_CLUSTER: ExecuteJobClusterTaskCreator,
        TaskEnum.GENERATE_DATABASE_TABLE_METRICS: GenerateDatabaseTableMetricsTaskCreator,
        TaskEnum.LOAD_CDC_CLEAN: LoadCDCCleanTaskCreator,
        TaskEnum.LOAD_CDC_RAW: LoadCDCRawTaskCreator,
        TaskEnum.LOAD_CDC_TRANSACTIONAL: LoadCDCTransactionalTaskCreator,
        TaskEnum.LOAD_API_RAW: LoadAPIRawTaskCreator,
        TaskEnum.LOAD_CUSTOM: LoadCustomTaskCreator,
        TaskEnum.LOAD_DMS_CDC_CLEAN: LoadDMSCDCCleanTaskCreator,
        TaskEnum.LOAD_DMS_CDC_RAW: LoadDMSCDCRawTaskCreator,
        TaskEnum.LOAD_MONGO_RAW: LoadMongoRawTaskCreator,
        TaskEnum.LOAD_POSTGRES_RAW: LoadPostgresRawTaskCreator,
        TaskEnum.LOAD_QUERY: LoadQueryTaskCreator,
        TaskEnum.LOAD_DELTA: LoadDeltaTableTaskCreator,
        TaskEnum.LOAD_CORE_MODEL: LoadCustomTaskCreator,
        TaskEnum.LOAD_WONKA: LoadWonkaTaskCreator,
        TaskEnum.OPTIMIZE_DELTA_TABLE: OptimizeDeltaTableTaskCreator,
        TaskEnum.REGISTER_DELTA_TABLE: RegisterDeltaTableTaskCreator,
        TaskEnum.REPROCESSING_GUARD: ReprocessingGuardTaskCreator,
        TaskEnum.SKIP_RUN: SkipRunTaskCreator,
        TaskEnum.SYNC_METADATA: SyncMetadataTaskCreator,
        TaskEnum.BUILD_QUBE_DIMENSION: BuildQubeDimensionTaskCreator,
        TaskEnum.BUILD_QUBE_MEASURE: BuildQubeMeasureTaskCreator,
        TaskEnum.BUILD_QUBE_METRIC: BuildQubeMetricTaskCreator,
        TaskEnum.QUBE_REGISTER_DELTA_TABLE: QubeRegisterDeltaTableTaskCreator,
        TaskEnum.CREATE_QUERY_VIEW: CreateQueryViewTaskCreator,
        TaskEnum.LOAD_CDF_TO_DATAZORD: LoadCDFtoDatazordTaskCreator,
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
                f"Database type '{database_type}' not supported. Supported databases are: {str(self.DATABASE_TYPES)}"
            )

        database_task_enum = TaskEnum[f"LOAD_{database_type.upper()}_RAW"]

        return self.get_task_creator(database_task_enum, *args, **kwargs)
