from qa_python_utils.default_logger import logger

from bietlejuice.jobs.new_etl.crm.tasks.tasks import CRMTasks


class CRMTasksPayment(CRMTasks):
    MANUAL_TASK_WORKGROUP_IDS = ['']

    TABLE_NAMES = {
        'fact': 'fact_payment_tasks',
        'dim': 'dim_payment_task'
    }

    @logger(exclude='mongo_client_uri')
    def __init__(self, s3_bucket, mongo_client_uri, execution_date):
        super(CRMTasksPayment, self).__init__(
            s3_bucket=s3_bucket,
            mongo_client_uri=mongo_client_uri,
            execution_date=execution_date
        )

    @logger
    def move_fact_to_staging(self):
        self._move_fact_to_staging(
            table_name=CRMTasksPayment.TABLE_NAMES['fact'],
            manual_task_workgroups=CRMTasksPayment.MANUAL_TASK_WORKGROUP_IDS
        )

    @logger
    def move_dim_to_staging(self):
        self._move_dim_to_staging(
            table_name=CRMTasksPayment.TABLE_NAMES['dim'],
            manual_task_workgroups=CRMTasksPayment.MANUAL_TASK_WORKGROUP_IDS
        )

    @logger
    def append_fact_to_dw(self):
        self._append_fact_to_dw(table_name=CRMTasksPayment.TABLE_NAMES['fact'])

    @logger
    def append_dim_to_dw(self):
        self._append_dim_to_dw(table_name=CRMTasksPayment.TABLE_NAMES['dim'])

    @logger
    def delete_staging_fact_entries(self):
        self._delete_staging_entries(table_name=CRMTasksPayment.TABLE_NAMES['fact'])

    @logger
    def delete_staging_dim_entries(self):
        self._delete_staging_entries(table_name=CRMTasksPayment.TABLE_NAMES['dim'])
