# encoding=utf-8
from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.crm.tasks.tasks import CRMTasks

logger = QuintoAndarLogger('CRMTasksLead')


class CRMTasksLead(CRMTasks):
    QUEUES = [
        'ConverterLead',
        'ConverterLeadPrioritario'
    ]

    TABLE_NAMES = {
        'fact': 'fact_lead_tasks',
        'dim': 'dim_lead_task'
    }

    QUERY_FILENAMES = {
        'staging': 'append_fact_lead_info.sql',
        'prod': 'append_fact_lead_table.sql'
    }

    @logger(exclude='mongo_client_uri')
    def __init__(self, s3_bucket, mongo_client_uri, execution_date):
        super(CRMTasksLead, self).__init__(
            s3_bucket=s3_bucket,
            mongo_client_uri=mongo_client_uri,
            execution_date=execution_date
        )

    @logger
    def move_fact_to_staging(self):
        self._move_fact_to_staging(
            table_name=CRMTasksLead.TABLE_NAMES['fact'],
            queues=CRMTasksLead.QUEUES,
            append_query_filename=CRMTasksLead.QUERY_FILENAMES['staging']
        )

    @logger
    def move_dim_to_staging(self):
        self._move_dim_to_staging(
            table_name=CRMTasksLead.TABLE_NAMES['dim'],
            queues=CRMTasksLead.QUEUES
        )

    @logger
    def append_fact_to_dw(self):
        self._append_fact_to_dw(
            table_name=CRMTasksLead.TABLE_NAMES['fact'],
            query_filename=CRMTasksLead.QUERY_FILENAMES['prod']
        )

    @logger
    def append_dim_to_dw(self):
        self._append_dim_to_dw(table_name=CRMTasksLead.TABLE_NAMES['dim'])

    @logger
    def delete_staging_fact_entries(self):
        self._delete_staging_entries(table_name=CRMTasksLead.TABLE_NAMES['fact'])

    @logger
    def delete_staging_dim_entries(self):
        self._delete_staging_entries(table_name=CRMTasksLead.TABLE_NAMES['dim'])
