import mock

from bietlejuice.jobs.etl.crm.tasks import CRMTasksInspection


class TestCRMTasksInspection(object):
    QUEUES = [
        'AgendarVistoria',
        'ConfirmarVistoriaEntrada',
        'FollowUpVistoriaEntrada',
        'EnviarVistoria',
        'AgendarVistoriaPreSaida',
        'AnalisarPreVistoria',
        'AgendarVistoriaSaida',
        'PrimeiraAnaliseVistoriaSaida',
        'EnviarPrimeiroResultadoSaida',
        'SegundaAnaliseVistoriaSaida',
        'EnviarSegundoResultadoSaida'
    ]

    MANUAL_TASK_WORKGROUP_IDS = [
        'EXIT_INSPECTION_TEAM',
        'DEP_VISTORIA_ID',
        'REVISIT_POSTCONTRACT_TEAM'
    ]

    TABLE_NAMES = {
        'fact': 'fact_inspection_tasks',
        'dim': 'dim_inspection_task'
    }

    QUERY_FILENAMES = {
        'staging': 'append_fact_inspection_info.sql',
        'prod': 'append_fact_inspection_table.sql'
    }

    @mock.patch.object(CRMTasksInspection, '_move_fact_to_staging')
    def test_move_fact_to_staging(self, mock__move_fact_to_staging, inspection):
        # arrange
        table_name = TestCRMTasksInspection.TABLE_NAMES['fact']
        queues = TestCRMTasksInspection.QUEUES
        manual_task_workgroups = TestCRMTasksInspection.MANUAL_TASK_WORKGROUP_IDS
        append_query_filename = TestCRMTasksInspection.QUERY_FILENAMES['staging']

        # act
        inspection.move_fact_to_staging()

        # assert
        assert mock__move_fact_to_staging.call_count == 1
        assert mock__move_fact_to_staging.call_args[1] == {
            'table_name': table_name,
            'queues': queues,
            'manual_task_workgroups': manual_task_workgroups,
            'append_query_filename': append_query_filename
        }

    @mock.patch.object(CRMTasksInspection, '_move_dim_to_staging')
    def test_move_dim_to_staging(self, mock__move_dim_to_staging, inspection):
        # arrange
        table_name = TestCRMTasksInspection.TABLE_NAMES['dim']
        queues = TestCRMTasksInspection.QUEUES
        manual_task_workgroups = TestCRMTasksInspection.MANUAL_TASK_WORKGROUP_IDS

        # act
        inspection.move_dim_to_staging()

        # assert
        assert mock__move_dim_to_staging.call_count == 1
        assert mock__move_dim_to_staging.call_args[1] == {
            'table_name': table_name,
            'queues': queues,
            'manual_task_workgroups': manual_task_workgroups
        }

    @mock.patch.object(CRMTasksInspection, '_append_fact_to_dw')
    def test_append_fact_to_dw(self, mock__append_fact_to_dw, inspection):
        # arrange
        table_name = TestCRMTasksInspection.TABLE_NAMES['fact']
        query_filename = TestCRMTasksInspection.QUERY_FILENAMES['prod']

        # act
        inspection.append_fact_to_dw()

        # assert
        assert mock__append_fact_to_dw.call_count == 1
        assert mock__append_fact_to_dw.call_args[1] == {
            'table_name': table_name,
            'query_filename': query_filename
        }

    @mock.patch.object(CRMTasksInspection, '_append_dim_to_dw')
    def test_append_dim_to_dw(self, mock__append_dim_to_dw, inspection):
        # arrange
        table_name = TestCRMTasksInspection.TABLE_NAMES['dim']

        # act
        inspection.append_dim_to_dw()

        # assert
        assert mock__append_dim_to_dw.call_count == 1
        assert mock__append_dim_to_dw.call_args[1] == {'table_name': table_name}

    @mock.patch.object(CRMTasksInspection, '_delete_staging_entries')
    def test_delete_staging_fact_entries(self, mock__delete_staging_entries, inspection):
        # arrange
        table_name = TestCRMTasksInspection.TABLE_NAMES['fact']

        # act
        inspection.delete_staging_fact_entries()

        # assert
        assert mock__delete_staging_entries.call_count == 1
        assert mock__delete_staging_entries.call_args[1] == {'table_name': table_name}

    @mock.patch.object(CRMTasksInspection, '_delete_staging_entries')
    def test_delete_staging_dim_entries(self, mock__delete_staging_entries, inspection):
        # arrange
        table_name = TestCRMTasksInspection.TABLE_NAMES['dim']

        # act
        inspection.delete_staging_dim_entries()

        # assert
        assert mock__delete_staging_entries.call_count == 1
        assert mock__delete_staging_entries.call_args[1] == {'table_name': table_name}
