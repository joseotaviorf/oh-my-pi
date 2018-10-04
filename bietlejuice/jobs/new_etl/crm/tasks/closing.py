from qa_python_utils.default_logger import logger

from bietlejuice.jobs.new_etl.crm.tasks.tasks import CRMTasks


class CRMTasksClosing(CRMTasks):
    QUEUES = ['FrontEnd', 'CriarMinuta', 'AprovarMinuta', 'FollowUpAssinaturas']

    TABLE_NAMES = {
        'fact': 'fact_closing_tasks',
        'dim': 'dim_closing_task'
    }

    @logger(exclude='mongo_client_uri')
    def __init__(self, s3_bucket, mongo_client_uri, execution_date):
        super(CRMTasksClosing, self).__init__(
            s3_bucket=s3_bucket,
            mongo_client_uri=mongo_client_uri,
            execution_date=execution_date
        )

    @logger
    def move_fact_to_staging(self):
        self._move_fact_to_staging(
            table_name=CRMTasksClosing.TABLE_NAMES['fact'],
            queues=CRMTasksClosing.QUEUES
        )

    @logger
    def move_dim_to_staging(self):
        self._move_dim_to_staging(
            table_name=CRMTasksClosing.TABLE_NAMES['dim'],
            queues=CRMTasksClosing.QUEUES
        )

    @logger
    def append_fact_to_dw(self):
        self._append_fact_to_dw(table_name=CRMTasksClosing.TABLE_NAMES['fact'])

    @logger
    def append_dim_to_dw(self):
        self._append_dim_to_dw(table_name=CRMTasksClosing.TABLE_NAMES['dim'])

    @logger
    def delete_staging_fact_entries(self):
        self._delete_staging_entries(table_name=CRMTasksClosing.TABLE_NAMES['fact'])

    @logger
    def delete_staging_dim_entries(self):
        self._delete_staging_entries(table_name=CRMTasksClosing.TABLE_NAMES['dim'])
