# encoding=utf-8
from qa_python_utils.default_logger import logger

from bietlejuice.jobs.new_etl.crm.tasks.tasks import CRMTasks


class CRMTasksOnboarding(CRMTasks):
    QUEUES = [
        'AgendarBuscaEEntregaDeChaves',
        'AtualizaInfoChavesProp',
        'AtualizaInfoChavesRecebidas',
        'BuscarChaveProprietario',
        'ConfirmarComprovantesContas',
        'ConfirmarDados',
        'ConfirmarLocalChaves',
        'ContatarInquilinoInfoEntregaChaves',
        'EntregaChavesParaInquilino',
        'EnviarVistoria',
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

    MANUAL_TASK_WORKGROUP_IDS = ['DEP_ONBOARDING_INQUILINO']

    TABLE_NAMES = {
        'fact': 'fact_onboarding_tenant_tasks',
        'dim': 'dim_onboarding_tenant_task'
    }

    QUERY_FILENAMES = {
        'fact': 'append_fact_onboarding_tenant_info.sql'
    }

    @logger(exclude='mongo_client_uri')
    def __init__(self, s3_bucket, mongo_client_uri, execution_date):
        super(CRMTasksOnboarding, self).__init__(
            s3_bucket=s3_bucket,
            mongo_client_uri=mongo_client_uri,
            execution_date=execution_date
        )

    @logger
    def move_fact_to_staging(self):
        self._move_fact_to_staging(
            table_name=CRMTasksOnboarding.TABLE_NAMES['fact'],
            queues=CRMTasksOnboarding.QUEUES,
            manual_task_workgroups=CRMTasksOnboarding.MANUAL_TASK_WORKGROUP_IDS,
            append_query_filename=CRMTasksOnboarding.QUERY_FILENAMES['fact']
        )

    @logger
    def move_dim_to_staging(self):
        self._move_dim_to_staging(
            table_name=CRMTasksOnboarding.TABLE_NAMES['dim'],
            queues=CRMTasksOnboarding.QUEUES,
            manual_task_workgroups=CRMTasksOnboarding.MANUAL_TASK_WORKGROUP_IDS
        )

    @logger
    def append_fact_to_dw(self):
        self._append_fact_to_dw(
            table_name=CRMTasksOnboarding.TABLE_NAMES['fact'],
            query_filename='append_fact_onboarding_tenant_table.sql'
        )

    @logger
    def append_dim_to_dw(self):
        self._append_dim_to_dw(table_name=CRMTasksOnboarding.TABLE_NAMES['dim'])

    @logger
    def delete_staging_fact_entries(self):
        self._delete_staging_entries(table_name=CRMTasksOnboarding.TABLE_NAMES['fact'])

    @logger
    def delete_staging_dim_entries(self):
        self._delete_staging_entries(table_name=CRMTasksOnboarding.TABLE_NAMES['dim'])
