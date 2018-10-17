from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.new_etl.crm.tasks.tasks import CRMTasks

logger = QuintoAndarLogger('CRMTasksPayment')


class CRMTasksPayment(CRMTasks):
    QUEUES = ['BuscarPrimeiroBoleto']

    MANUAL_TASK_WORKGROUP_IDS = [
        'DEP_FINANCEIRO_ID',
        'DEP_PAYMENTS_SELFCONDO',
        'DEP_OFFBOARDING_FINANCEIRO',
        'DEP_ACORDOS_DESCONTOS_ID'
    ]

    TABLE_NAMES = {
        'fact': 'fact_payment_tasks',
        'dim': 'dim_payment_task'
    }

    QUERY_FILENAMES = {
        'staging': 'append_fact_payment_info.sql',
        'prod': 'append_fact_payment_table.sql'
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
            queues=CRMTasksPayment.QUEUES,
            manual_task_workgroups=CRMTasksPayment.MANUAL_TASK_WORKGROUP_IDS,
            append_query_filename=CRMTasksPayment.QUERY_FILENAMES['staging']
        )

    @logger
    def move_dim_to_staging(self):
        self._move_dim_to_staging(
            table_name=CRMTasksPayment.TABLE_NAMES['dim'],
            queues=CRMTasksPayment.QUEUES,
            manual_task_workgroups=CRMTasksPayment.MANUAL_TASK_WORKGROUP_IDS
        )

    @logger
    def append_fact_to_dw(self):
        self._append_fact_to_dw(
            table_name=CRMTasksPayment.TABLE_NAMES['fact'],
            query_filename=CRMTasksPayment.QUERY_FILENAMES['prod']
        )

    @logger
    def append_dim_to_dw(self):
        self._append_dim_to_dw(table_name=CRMTasksPayment.TABLE_NAMES['dim'])

    @logger
    def delete_staging_fact_entries(self):
        self._delete_staging_entries(table_name=CRMTasksPayment.TABLE_NAMES['fact'])

    @logger
    def delete_staging_dim_entries(self):
        self._delete_staging_entries(table_name=CRMTasksPayment.TABLE_NAMES['dim'])
