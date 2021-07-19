# encoding=utf-8
from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.crm.tasks.tasks import CRMTasks

logger = QuintoAndarLogger('CRMTasksOnboardingTenant')


class CRMTasksOnboardingTenant(CRMTasks):
    QUEUES = [
        'AgendarBuscaEEntregaDeChaves',
        'AtualizaInfoChavesProp',
        'AtualizaInfoChavesRecebidas',
        'BuscarChaveProprietario',
        'ConfirmarComprovantesContas',
        'ConfirmarDados',
        'ConfirmarLocalChaves',
        'ContatarInquilinoInfoEntregaChaves',
        'DevolverChavesParaProprietarios',
        'EntregaChavesParaInquilino',
        'InquilinoNaoRecebeuTodasChaves',
        'PagarContasConsumo',
        'SendLongTermEmailOwner',
        'SendLongTermEmailTenant',
        'SendShortTerm',
        'TransferenciaContasConsumoAgua',
        'TransferenciaContasConsumoGas',
        'TransferenciaContasConsumoLuz',
        'VerificarContrato'
    ]

    MANUAL_TASK_WORKGROUP_IDS = [
        'DEP_ONBOARDING_INQUILINO',
        'DEP_KEY_TRAVEL_AFTER_EXIT'
    ]

    TABLE_NAMES = {
        'fact': 'fact_onboarding_tenant_tasks',
        'dim': 'dim_onboarding_tenant_task'
    }

    QUERY_FILENAMES = {
        'staging': 'append_fact_onboarding_tenant_info.sql',
        'prod': 'append_fact_onboarding_tenant_table.sql'
    }

    @logger(exclude='mongo_client_uri')
    def __init__(self, s3_bucket, mongo_client_uri, execution_date):
        super(CRMTasksOnboardingTenant, self).__init__(
            s3_bucket=s3_bucket,
            mongo_client_uri=mongo_client_uri,
            execution_date=execution_date
        )

    @logger
    def move_fact_to_staging(self):
        self._move_fact_to_staging(
            table_name=CRMTasksOnboardingTenant.TABLE_NAMES['fact'],
            queues=CRMTasksOnboardingTenant.QUEUES,
            manual_task_workgroups=CRMTasksOnboardingTenant.MANUAL_TASK_WORKGROUP_IDS,
            append_query_filename=CRMTasksOnboardingTenant.QUERY_FILENAMES['staging']
        )

    @logger
    def move_dim_to_staging(self):
        self._move_dim_to_staging(
            table_name=CRMTasksOnboardingTenant.TABLE_NAMES['dim'],
            queues=CRMTasksOnboardingTenant.QUEUES,
            manual_task_workgroups=CRMTasksOnboardingTenant.MANUAL_TASK_WORKGROUP_IDS
        )

    @logger
    def append_fact_to_dw(self):
        self._append_fact_to_dw(
            table_name=CRMTasksOnboardingTenant.TABLE_NAMES['fact'],
            query_filename=CRMTasksOnboardingTenant.QUERY_FILENAMES['prod']
        )

    @logger
    def append_dim_to_dw(self):
        self._append_dim_to_dw(table_name=CRMTasksOnboardingTenant.TABLE_NAMES['dim'])

    @logger
    def delete_staging_fact_entries(self):
        self._delete_staging_entries(table_name=CRMTasksOnboardingTenant.TABLE_NAMES['fact'])

    @logger
    def delete_staging_dim_entries(self):
        self._delete_staging_entries(table_name=CRMTasksOnboardingTenant.TABLE_NAMES['dim'])
