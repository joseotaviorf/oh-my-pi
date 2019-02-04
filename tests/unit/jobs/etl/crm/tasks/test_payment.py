import mock

from bietlejuice.jobs.etl.crm.tasks import CRMTasksPayment


class TestCRMTasksPayment(object):
    QUEUES = [
        'BuscarPrimeiroBoleto',
        'PedidoDeReembolso',
        'ConfirmarBoletoCondominio'
    ]

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

    @mock.patch.object(CRMTasksPayment, '_move_fact_to_staging')
    def test_move_fact_to_staging(self, mock__move_fact_to_staging, payment):
        # arrange
        table_name = TestCRMTasksPayment.TABLE_NAMES['fact']
        queues = TestCRMTasksPayment.QUEUES
        manual_task_workgroups = TestCRMTasksPayment.MANUAL_TASK_WORKGROUP_IDS
        append_query_filename = TestCRMTasksPayment.QUERY_FILENAMES['staging']

        # act
        payment.move_fact_to_staging()

        # assert
        assert mock__move_fact_to_staging.call_count == 1
        assert mock__move_fact_to_staging.call_args[1] == {
            'table_name': table_name,
            'queues': queues,
            'manual_task_workgroups': manual_task_workgroups,
            'append_query_filename': append_query_filename
        }

    @mock.patch.object(CRMTasksPayment, '_move_dim_to_staging')
    def test_move_dim_to_staging(self, mock__move_dim_to_staging, payment):
        # arrange
        table_name = TestCRMTasksPayment.TABLE_NAMES['dim']
        queues = TestCRMTasksPayment.QUEUES
        manual_task_workgroups = TestCRMTasksPayment.MANUAL_TASK_WORKGROUP_IDS

        # act
        payment.move_dim_to_staging()

        # assert
        assert mock__move_dim_to_staging.call_count == 1
        assert mock__move_dim_to_staging.call_args[1] == {
            'table_name': table_name,
            'queues': queues,
            'manual_task_workgroups': manual_task_workgroups
        }

    @mock.patch.object(CRMTasksPayment, '_append_fact_to_dw')
    def test_append_fact_to_dw(self, mock__append_fact_to_dw, payment):
        # arrange
        table_name = TestCRMTasksPayment.TABLE_NAMES['fact']
        query_filename = TestCRMTasksPayment.QUERY_FILENAMES['prod']

        # act
        payment.append_fact_to_dw()

        # assert
        assert mock__append_fact_to_dw.call_count == 1
        assert mock__append_fact_to_dw.call_args[1] == {
            'table_name': table_name,
            'query_filename': query_filename
        }

    @mock.patch.object(CRMTasksPayment, '_append_dim_to_dw')
    def test_append_dim_to_dw(self, mock__append_dim_to_dw, payment):
        # arrange
        table_name = TestCRMTasksPayment.TABLE_NAMES['dim']

        # act
        payment.append_dim_to_dw()

        # assert
        assert mock__append_dim_to_dw.call_count == 1
        assert mock__append_dim_to_dw.call_args[1] == {'table_name': table_name}

    @mock.patch.object(CRMTasksPayment, '_delete_staging_entries')
    def test_delete_staging_fact_entries(self, mock__delete_staging_entries, payment):
        # arrange
        table_name = TestCRMTasksPayment.TABLE_NAMES['fact']

        # act
        payment.delete_staging_fact_entries()

        # assert
        assert mock__delete_staging_entries.call_count == 1
        assert mock__delete_staging_entries.call_args[1] == {'table_name': table_name}

    @mock.patch.object(CRMTasksPayment, '_delete_staging_entries')
    def test_delete_staging_dim_entries(self, mock__delete_staging_entries, payment):
        # arrange
        table_name = TestCRMTasksPayment.TABLE_NAMES['dim']

        # act
        payment.delete_staging_dim_entries()

        # assert
        assert mock__delete_staging_entries.call_count == 1
        assert mock__delete_staging_entries.call_args[1] == {'table_name': table_name}
