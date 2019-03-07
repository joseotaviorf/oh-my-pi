import mock

from bietlejuice.jobs.etl.crm.tasks import CRMTasksChatLinhaDireta


class TestCRMTasksChatLinhaDireta(object):
    QUEUES = [
        'ChatIniciado',
        'ChatAtencaoSolicitada',
        'RevisarChat'
    ]

    TABLE_NAMES = {
        'fact': 'fact_linhadireta_chat_tasks',
        'dim': 'dim_linhadireta_chat_task'
    }

    QUERY_FILENAMES = {
        'staging': 'append_fact_linhadireta_chat_info.sql',
        'prod': 'append_fact_linhadireta_chat_table.sql'
    }

    @mock.patch.object(CRMTasksChatLinhaDireta, '_move_fact_to_staging')
    def test_move_fact_to_staging(self, mock__move_fact_to_staging, linhadireta_chat):
        # arrange
        table_name = TestCRMTasksChatLinhaDireta.TABLE_NAMES['fact']
        queues = TestCRMTasksChatLinhaDireta.QUEUES
        append_query_filename = TestCRMTasksChatLinhaDireta.QUERY_FILENAMES['staging']

        # act
        linhadireta_chat.move_fact_to_staging()

        # assert
        assert mock__move_fact_to_staging.call_count == 1
        assert mock__move_fact_to_staging.call_args[1] == {
            'table_name': table_name,
            'queues': queues,
            'append_query_filename': append_query_filename
        }

    @mock.patch.object(CRMTasksChatLinhaDireta, '_move_dim_to_staging')
    def test_move_dim_to_staging(self, mock__move_dim_to_staging, linhadireta_chat):
        # arrange
        table_name = TestCRMTasksChatLinhaDireta.TABLE_NAMES['dim']
        queues = TestCRMTasksChatLinhaDireta.QUEUES

        # act
        linhadireta_chat.move_dim_to_staging()

        # assert
        assert mock__move_dim_to_staging.call_count == 1
        assert mock__move_dim_to_staging.call_args[1] == {
            'table_name': table_name,
            'queues': queues
        }

    @mock.patch.object(CRMTasksChatLinhaDireta, '_append_fact_to_dw')
    def test_append_fact_to_dw(self, mock__append_fact_to_dw, linhadireta_chat):
        # arrange
        table_name = TestCRMTasksChatLinhaDireta.TABLE_NAMES['fact']
        query_filename = TestCRMTasksChatLinhaDireta.QUERY_FILENAMES['prod']

        # act
        linhadireta_chat.append_fact_to_dw()

        # assert
        assert mock__append_fact_to_dw.call_count == 1
        assert mock__append_fact_to_dw.call_args[1] == {
            'table_name': table_name,
            'query_filename': query_filename
        }

    @mock.patch.object(CRMTasksChatLinhaDireta, '_append_dim_to_dw')
    def test_append_dim_to_dw(self, mock__append_dim_to_dw, linhadireta_chat):
        # arrange
        table_name = TestCRMTasksChatLinhaDireta.TABLE_NAMES['dim']

        # act
        linhadireta_chat.append_dim_to_dw()

        # assert
        assert mock__append_dim_to_dw.call_count == 1
        assert mock__append_dim_to_dw.call_args[1] == {'table_name': table_name}

    @mock.patch.object(CRMTasksChatLinhaDireta, '_delete_staging_entries')
    def test_delete_staging_fact_entries(self, mock__delete_staging_entries, linhadireta_chat):
        # arrange
        table_name = TestCRMTasksChatLinhaDireta.TABLE_NAMES['fact']

        # act
        linhadireta_chat.delete_staging_fact_entries()

        # assert
        assert mock__delete_staging_entries.call_count == 1
        assert mock__delete_staging_entries.call_args[1] == {'table_name': table_name}

    @mock.patch.object(CRMTasksChatLinhaDireta, '_delete_staging_entries')
    def test_delete_staging_dim_entries(self, mock__delete_staging_entries, linhadireta_chat):
        # arrange
        table_name = TestCRMTasksChatLinhaDireta.TABLE_NAMES['dim']

        # act
        linhadireta_chat.delete_staging_dim_entries()

        # assert
        assert mock__delete_staging_entries.call_count == 1
        assert mock__delete_staging_entries.call_args[1] == {'table_name': table_name}
