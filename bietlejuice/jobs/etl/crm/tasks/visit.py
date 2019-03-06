from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.crm.tasks.tasks import CRMTasks

logger = QuintoAndarLogger('CRMTasksVisit')


class CRMTasksVisit(CRMTasks):
    QUEUES = [
        'ConfirmarAgendamento',
        'ConfirmarCondicoesEntrada'
    ]

    TABLE_NAMES = {
        'fact': 'fact_visit_tasks',
        'dim': 'dim_visit_task'
    }

    QUERY_FILENAMES = {
        'staging': 'append_fact_visit_info.sql',
        'prod': 'append_fact_visit_table.sql'
    }

    @logger(exclude='mongo_client_uri')
    def __init__(self, s3_bucket, mongo_client_uri, execution_date):
        super(CRMTasksVisit, self).__init__(
            s3_bucket=s3_bucket,
            mongo_client_uri=mongo_client_uri,
            execution_date=execution_date
        )

    @logger
    def move_fact_to_staging(self):
        self._move_fact_to_staging(
            table_name=CRMTasksVisit.TABLE_NAMES['fact'],
            queues=CRMTasksVisit.QUEUES,
            append_query_filename=CRMTasksVisit.QUERY_FILENAMES['staging']
        )

    @logger
    def move_dim_to_staging(self):
        self._move_dim_to_staging(
            table_name=CRMTasksVisit.TABLE_NAMES['dim'],
            queues=CRMTasksVisit.QUEUES
        )

    @logger
    def append_fact_to_dw(self):
        self._append_fact_to_dw(
            table_name=CRMTasksVisit.TABLE_NAMES['fact'],
            query_filename=CRMTasksVisit.QUERY_FILENAMES['prod']
        )

    @logger
    def append_dim_to_dw(self):
        self._append_dim_to_dw(table_name=CRMTasksVisit.TABLE_NAMES['dim'])

    @logger
    def delete_staging_fact_entries(self):
        self._delete_staging_entries(table_name=CRMTasksVisit.TABLE_NAMES['fact'])

    @logger
    def delete_staging_dim_entries(self):
        self._delete_staging_entries(table_name=CRMTasksVisit.TABLE_NAMES['dim'])
