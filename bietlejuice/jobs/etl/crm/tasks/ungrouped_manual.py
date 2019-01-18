from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.crm.tasks.tasks import CRMTasks

logger = QuintoAndarLogger('CRMTasksUngroupedManual')


class CRMTasksUngroupedManual(CRMTasks):
    TABLE_NAMES = {
        'fact': 'fact_ungrouped_manual_tasks',
        'dim': 'dim_ungrouped_manual_task'
    }

    @logger(exclude='mongo_client_uri')
    def __init__(self, s3_bucket, mongo_client_uri, execution_date):
        super(CRMTasksUngroupedManual, self).__init__(
            s3_bucket=s3_bucket,
            mongo_client_uri=mongo_client_uri,
            execution_date=execution_date
        )

    @logger
    def move_fact_to_staging(self):
        self._move_fact_to_staging(table_name=CRMTasksUngroupedManual.TABLE_NAMES['fact'])

    @logger
    def move_dim_to_staging(self):
        self._move_dim_to_staging(table_name=CRMTasksUngroupedManual.TABLE_NAMES['dim'])

    @logger
    def append_fact_to_dw(self):
        self._append_fact_to_dw(table_name=CRMTasksUngroupedManual.TABLE_NAMES['fact'])

    @logger
    def append_dim_to_dw(self):
        self._append_dim_to_dw(table_name=CRMTasksUngroupedManual.TABLE_NAMES['dim'])

    @logger
    def delete_staging_fact_entries(self):
        self._delete_staging_entries(table_name=CRMTasksUngroupedManual.TABLE_NAMES['fact'])

    @logger
    def delete_staging_dim_entries(self):
        self._delete_staging_entries(table_name=CRMTasksUngroupedManual.TABLE_NAMES['dim'])
