from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.crm.tasks.tasks import CRMTasks

logger = QuintoAndarLogger('CRMTasksOffboarding')


class CRMTasksOffboarding(CRMTasks):
    QUEUES = [
        'DataDeRescisaoAlterada',
        'EncerrarContrato',
        'FollowUpReparosRescisao',
        'OrientarInquilinoRescisao',
        'OrientarProprietarioRescisao',
        'OrientarInquilinoDesocupacao',
        'ProtecaoReparosRescisao',
        'RescisaoCancelada',
        'RevisarCancelamentoDeRescisao',
        'RevisarPagamentosRescisao',
        'VerificarDesocupacaoImovel'
    ]

    MANUAL_TASK_WORKGROUP_IDS = [
        'DEP_OFFBOARDING_2',
        'DEP_OFFBOARDING_ID',
        'DEP_OFFBOARDING_WORKFLOW_ID',
        'DEP_OFFBOARDING_WORKFLOW_STEP_ONE_ID',
        'DEP_OFFBOARDING_WORKFLOW_STEP_TWO_ID',
        'DEP_OFFBOARDING_WORKFLOW_STEP_THREE_ID'
    ]

    TABLE_NAMES = {
        'fact': 'fact_offboarding_tasks',
        'dim': 'dim_offboarding_task'
    }

    QUERY_FILENAMES = {
        'staging': 'append_fact_offboarding_info.sql',
        'prod': 'append_fact_offboarding_table.sql'
    }

    # TODO remove mongo_client_uri from child classes
    @logger
    def __init__(self, s3_bucket, execution_date, mongo_client_uri=None):
        super(CRMTasksOffboarding, self).__init__(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @logger
    def move_fact_to_staging(self):
        self._move_fact_to_staging(
            table_name=CRMTasksOffboarding.TABLE_NAMES['fact'],
            queues=CRMTasksOffboarding.QUEUES,
            manual_task_workgroups=CRMTasksOffboarding.MANUAL_TASK_WORKGROUP_IDS,
            append_query_filename=CRMTasksOffboarding.QUERY_FILENAMES['staging']
        )

    @logger
    def move_dim_to_staging(self):
        self._move_dim_to_staging(
            table_name=CRMTasksOffboarding.TABLE_NAMES['dim'],
            queues=CRMTasksOffboarding.QUEUES,
            manual_task_workgroups=CRMTasksOffboarding.MANUAL_TASK_WORKGROUP_IDS
        )

    @logger
    def append_fact_to_dw(self):
        self._append_fact_to_dw(
            table_name=CRMTasksOffboarding.TABLE_NAMES['fact'],
            query_filename=CRMTasksOffboarding.QUERY_FILENAMES['prod']
        )

    @logger
    def append_dim_to_dw(self):
        self._append_dim_to_dw(table_name=CRMTasksOffboarding.TABLE_NAMES['dim'])

    @logger
    def delete_staging_fact_entries(self):
        self._delete_staging_entries(table_name=CRMTasksOffboarding.TABLE_NAMES['fact'])

    @logger
    def delete_staging_dim_entries(self):
        self._delete_staging_entries(table_name=CRMTasksOffboarding.TABLE_NAMES['dim'])
