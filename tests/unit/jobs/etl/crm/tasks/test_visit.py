import mock

from bietlejuice.jobs.etl.crm.tasks import CRMTasksVisit


class TestCRMTasksVisit(object):
    QUEUES = [
        'ConfirmarAgendamento',
        'ConfirmarCondicoesEntrada'
    ]

    TABLE_NAMES = {
        'fact': 'fact_visit_tasks',
        'dim': 'dim_visit_task'
    }

    QUERY_FILENAMES = {
        'staging': 'append_fact_visit_info.sql',
        'prod': 'append_fact_visit_table.sql'
    }

    @mock.patch.object(CRMTasksVisit, '_move_fact_to_staging')
    def test_move_fact_to_staging(self, mock__move_fact_to_staging, visit):
        # arrange
        table_name = TestCRMTasksVisit.TABLE_NAMES['fact']
        queues = TestCRMTasksVisit.QUEUES
        append_query_filename = TestCRMTasksVisit.QUERY_FILENAMES['staging']

        # act
        visit.move_fact_to_staging()

        # assert
        assert mock__move_fact_to_staging.call_count == 1
        assert mock__move_fact_to_staging.call_args[1] == {
            'table_name': table_name,
            'queues': queues,
            'append_query_filename': append_query_filename
        }

    @mock.patch.object(CRMTasksVisit, '_move_dim_to_staging')
    def test_move_dim_to_staging(self, mock__move_dim_to_staging, visit):
        # arrange
        table_name = TestCRMTasksVisit.TABLE_NAMES['dim']
        queues = TestCRMTasksVisit.QUEUES

        # act
        visit.move_dim_to_staging()

        # assert
        assert mock__move_dim_to_staging.call_count == 1
        assert mock__move_dim_to_staging.call_args[1] == {
            'table_name': table_name,
            'queues': queues
        }

    @mock.patch.object(CRMTasksVisit, '_append_fact_to_dw')
    def test_append_fact_to_dw(self, mock__append_fact_to_dw, visit):
        # arrange
        table_name = TestCRMTasksVisit.TABLE_NAMES['fact']
        query_filename = TestCRMTasksVisit.QUERY_FILENAMES['prod']

        # act
        visit.append_fact_to_dw()

        # assert
        assert mock__append_fact_to_dw.call_count == 1
        assert mock__append_fact_to_dw.call_args[1] == {
            'table_name': table_name,
            'query_filename': query_filename
        }

    @mock.patch.object(CRMTasksVisit, '_append_dim_to_dw')
    def test_append_dim_to_dw(self, mock__append_dim_to_dw, visit):
        # arrange
        table_name = TestCRMTasksVisit.TABLE_NAMES['dim']

        # act
        visit.append_dim_to_dw()

        # assert
        assert mock__append_dim_to_dw.call_count == 1
        assert mock__append_dim_to_dw.call_args[1] == {'table_name': table_name}

    @mock.patch.object(CRMTasksVisit, '_delete_staging_entries')
    def test_delete_staging_fact_entries(self, mock__delete_staging_entries, visit):
        # arrange
        table_name = TestCRMTasksVisit.TABLE_NAMES['fact']

        # act
        visit.delete_staging_fact_entries()

        # assert
        assert mock__delete_staging_entries.call_count == 1
        assert mock__delete_staging_entries.call_args[1] == {'table_name': table_name}

    @mock.patch.object(CRMTasksVisit, '_delete_staging_entries')
    def test_delete_staging_dim_entries(self, mock__delete_staging_entries, visit):
        # arrange
        table_name = TestCRMTasksVisit.TABLE_NAMES['dim']

        # act
        visit.delete_staging_dim_entries()

        # assert
        assert mock__delete_staging_entries.call_count == 1
        assert mock__delete_staging_entries.call_args[1] == {'table_name': table_name}
