# encoding=utf-8
from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.crm.tasks.tasks import CRMTasks

logger = QuintoAndarLogger('CRMTasksInspection')


class CRMTasksInspection(CRMTasks):
    QUEUES = [
        'AgendarVistoria',
        'ConfirmarVistoriaEntrada',
        'FollowUpVistoriaEntrada',
        'EnviarVistoria',
        'AgendarVistoriaPreSaida',
        'AnalisarPreVistoria',
        'AgendarVistoriaSaida',
        'PrimeiraAnaliseVistoriaSaida',
        'EnviarPrimeiroResultadoSaida',
        'SegundaAnaliseVistoriaSaida',
        'EnviarSegundoResultadoSaida'
    ]

    MANUAL_TASK_WORKGROUP_IDS = [
        'EXIT_INSPECTION_TEAM',
        'DEP_VISTORIA_ID',
        'REVISIT_POSTCONTRACT_TEAM'
    ]

    TABLE_NAMES = {
        'fact': 'fact_inspection_tasks',
        'dim': 'dim_inspection_task'
    }

    QUERY_FILENAMES = {
        'staging': 'append_fact_inspection_info.sql',
        'prod': 'append_fact_inspection_table.sql'
    }

    @logger(exclude='mongo_client_uri')
    def __init__(self, s3_bucket, mongo_client_uri, execution_date):
        super(CRMTasksInspection, self).__init__(
            s3_bucket=s3_bucket,
            mongo_client_uri=mongo_client_uri,
            execution_date=execution_date
        )

    @logger
    def move_fact_to_staging(self):
        self._move_fact_to_staging(
            table_name=CRMTasksInspection.TABLE_NAMES['fact'],
            queues=CRMTasksInspection.QUEUES,
            manual_task_workgroups=CRMTasksInspection.MANUAL_TASK_WORKGROUP_IDS,
            append_query_filename=CRMTasksInspection.QUERY_FILENAMES['staging']
        )

    @logger
    def move_dim_to_staging(self):
        self._move_dim_to_staging(
            table_name=CRMTasksInspection.TABLE_NAMES['dim'],
            queues=CRMTasksInspection.QUEUES,
            manual_task_workgroups=CRMTasksInspection.MANUAL_TASK_WORKGROUP_IDS
        )

    @logger
    def append_fact_to_dw(self):
        self._append_fact_to_dw(
            table_name=CRMTasksInspection.TABLE_NAMES['fact'],
            query_filename=CRMTasksInspection.QUERY_FILENAMES['prod']
        )

    @logger
    def append_dim_to_dw(self):
        self._append_dim_to_dw(table_name=CRMTasksInspection.TABLE_NAMES['dim'])

    @logger
    def delete_staging_fact_entries(self):
        self._delete_staging_entries(table_name=CRMTasksInspection.TABLE_NAMES['fact'])

    @logger
    def delete_staging_dim_entries(self):
        self._delete_staging_entries(table_name=CRMTasksInspection.TABLE_NAMES['dim'])
