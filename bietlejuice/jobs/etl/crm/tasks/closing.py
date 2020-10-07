from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.crm.task_status_histories.task_status_histories import CRMTaskStatusHistories

logger = QuintoAndarLogger('CRMTasksClosing')


class CRMTasksClosing(CRMTaskStatusHistories):
    QUEUES = [
        'FrontEnd',
        'CriarMinuta',
        'AprovarMinuta',
        'FollowUpAssinaturas',
        'EnviarContratoViaEmail',
        'AnalisarDocumentacaoProprietario',
        'AlinhamentoComPP',
        'VerificacaoComIQ'
    ]

    MANUAL_TASK_WORKGROUP_IDS = [
        'DEP_CLOSING_ID'
    ]

    TABLE_NAMES = {
        'fact': 'fact_closing_tasks',
        'dim': 'dim_closing_task'
    }

    QUERY_FILENAMES = {
        'staging': 'append_fact_closing_info.sql',
        'prod': 'append_fact_closing_table.sql'
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
            queues=CRMTasksClosing.QUEUES,
            manual_task_workgroups=CRMTasksClosing.MANUAL_TASK_WORKGROUP_IDS,
            append_query_filename=CRMTasksClosing.QUERY_FILENAMES['staging']
        )

    @logger
    def move_dim_to_staging(self):
        self._move_dim_to_staging(
            table_name=CRMTasksClosing.TABLE_NAMES['dim'],
            queues=CRMTasksClosing.QUEUES,
            manual_task_workgroups=CRMTasksClosing.MANUAL_TASK_WORKGROUP_IDS,
        )

    @logger
    def append_fact_to_dw(self):
        self._append_fact_to_dw(
            table_name=CRMTasksClosing.TABLE_NAMES['fact'],
            query_filename=CRMTasksClosing.QUERY_FILENAMES['prod']
        )

    @logger
    def append_dim_to_dw(self):
        self._append_dim_to_dw(table_name=CRMTasksClosing.TABLE_NAMES['dim'])

    @logger
    def delete_staging_fact_entries(self):
        self._delete_staging_entries(table_name=CRMTasksClosing.TABLE_NAMES['fact'])

    @logger
    def delete_staging_dim_entries(self):
        self._delete_staging_entries(table_name=CRMTasksClosing.TABLE_NAMES['dim'])
