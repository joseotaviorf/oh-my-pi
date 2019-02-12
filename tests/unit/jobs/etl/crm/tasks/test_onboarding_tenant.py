import mock

from bietlejuice.jobs.etl.crm.tasks import CRMTasksOnboardingTenant


class TestCRMTasksOnboardingTenant(object):
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
        'staging': 'append_fact_onboarding_tenant_info.sql',
        'prod': 'append_fact_onboarding_tenant_table.sql'
    }

    @mock.patch.object(CRMTasksOnboardingTenant, '_move_fact_to_staging')
    def test_move_fact_to_staging(self, mock__move_fact_to_staging, onboarding_tenant):
        # arrange
        table_name = TestCRMTasksOnboardingTenant.TABLE_NAMES['fact']
        queues = TestCRMTasksOnboardingTenant.QUEUES
        manual_task_workgroups = TestCRMTasksOnboardingTenant.MANUAL_TASK_WORKGROUP_IDS
        append_query_filename = TestCRMTasksOnboardingTenant.QUERY_FILENAMES['staging']

        # act
        onboarding_tenant.move_fact_to_staging()

        # assert
        assert mock__move_fact_to_staging.call_count == 1
        assert mock__move_fact_to_staging.call_args[1] == {
            'table_name': table_name,
            'queues': queues,
            'manual_task_workgroups': manual_task_workgroups,
            'append_query_filename': append_query_filename
        }

    @mock.patch.object(CRMTasksOnboardingTenant, '_move_dim_to_staging')
    def test_move_dim_to_staging(self, mock__move_dim_to_staging, onboarding_tenant):
        # arrange
        table_name = TestCRMTasksOnboardingTenant.TABLE_NAMES['dim']
        queues = TestCRMTasksOnboardingTenant.QUEUES
        manual_task_workgroups = TestCRMTasksOnboardingTenant.MANUAL_TASK_WORKGROUP_IDS

        # act
        onboarding_tenant.move_dim_to_staging()

        # assert
        assert mock__move_dim_to_staging.call_count == 1
        assert mock__move_dim_to_staging.call_args[1] == {
            'table_name': table_name,
            'queues': queues,
            'manual_task_workgroups': manual_task_workgroups
        }

    @mock.patch.object(CRMTasksOnboardingTenant, '_append_fact_to_dw')
    def test_append_fact_to_dw(self, mock__append_fact_to_dw, onboarding_tenant):
        # arrange
        table_name = TestCRMTasksOnboardingTenant.TABLE_NAMES['fact']
        query_filename = TestCRMTasksOnboardingTenant.QUERY_FILENAMES['prod']

        # act
        onboarding_tenant.append_fact_to_dw()

        # assert
        assert mock__append_fact_to_dw.call_count == 1
        assert mock__append_fact_to_dw.call_args[1] == {
            'table_name': table_name,
            'query_filename': query_filename
        }

    @mock.patch.object(CRMTasksOnboardingTenant, '_append_dim_to_dw')
    def test_append_dim_to_dw(self, mock__append_dim_to_dw, onboarding_tenant):
        # arrange
        table_name = TestCRMTasksOnboardingTenant.TABLE_NAMES['dim']

        # act
        onboarding_tenant.append_dim_to_dw()

        # assert
        assert mock__append_dim_to_dw.call_count == 1
        assert mock__append_dim_to_dw.call_args[1] == {'table_name': table_name}

    @mock.patch.object(CRMTasksOnboardingTenant, '_delete_staging_entries')
    def test_delete_staging_fact_entries(self, mock__delete_staging_entries, onboarding_tenant):
        # arrange
        table_name = TestCRMTasksOnboardingTenant.TABLE_NAMES['fact']

        # act
        onboarding_tenant.delete_staging_fact_entries()

        # assert
        assert mock__delete_staging_entries.call_count == 1
        assert mock__delete_staging_entries.call_args[1] == {'table_name': table_name}

    @mock.patch.object(CRMTasksOnboardingTenant, '_delete_staging_entries')
    def test_delete_staging_dim_entries(self, mock__delete_staging_entries, onboarding_tenant):
        # arrange
        table_name = TestCRMTasksOnboardingTenant.TABLE_NAMES['dim']

        # act
        onboarding_tenant.delete_staging_dim_entries()

        # assert
        assert mock__delete_staging_entries.call_count == 1
        assert mock__delete_staging_entries.call_args[1] == {'table_name': table_name}
