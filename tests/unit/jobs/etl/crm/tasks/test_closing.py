import mock

from bietlejuice.jobs.etl.crm.tasks import CRMTasksClosing


class TestCRMTasksClosing(object):
    QUEUES = [
        'FrontEnd',
        'CriarMinuta',
        'AprovarMinuta',
        'FollowUpAssinaturas'
    ]

    TABLE_NAMES = {
        'fact': 'fact_closing_tasks',
        'dim': 'dim_closing_task'
    }

    QUERY_FILENAMES = {
        'staging': 'append_fact_closing_info.sql',
        'prod': 'append_fact_closing_table.sql'
    }

    @mock.patch.object(CRMTasksClosing, '_move_fact_to_staging')
    def test_move_fact_to_staging(self, mock__move_fact_to_staging, closing):
        # arrange
        table_name = TestCRMTasksClosing.TABLE_NAMES['fact']
        queues = TestCRMTasksClosing.QUEUES
        append_query_filename = TestCRMTasksClosing.QUERY_FILENAMES['staging']

        # act
        closing.move_fact_to_staging()

        # assert
        assert mock__move_fact_to_staging.call_count == 1
        assert mock__move_fact_to_staging.call_args[1] == {
            'table_name': table_name,
            'queues': queues,
            'append_query_filename': append_query_filename
        }

    @mock.patch.object(CRMTasksClosing, '_move_dim_to_staging')
    def test_move_dim_to_staging(self, mock__move_dim_to_staging, closing):
        # arrange
        table_name = TestCRMTasksClosing.TABLE_NAMES['dim']
        queues = TestCRMTasksClosing.QUEUES

        # act
        closing.move_dim_to_staging()

        # assert
        assert mock__move_dim_to_staging.call_count == 1
        assert mock__move_dim_to_staging.call_args[1] == {
            'table_name': table_name,
            'queues': queues
        }

    @mock.patch.object(CRMTasksClosing, '_append_fact_to_dw')
    def test_append_fact_to_dw(self, mock__append_fact_to_dw, closing):
        # arrange
        table_name = TestCRMTasksClosing.TABLE_NAMES['fact']
        query_filename = TestCRMTasksClosing.QUERY_FILENAMES['prod']

        # act
        closing.append_fact_to_dw()

        # assert
        assert mock__append_fact_to_dw.call_count == 1
        assert mock__append_fact_to_dw.call_args[1] == {
            'table_name': table_name,
            'query_filename': query_filename
        }

    @mock.patch.object(CRMTasksClosing, '_append_dim_to_dw')
    def test_append_dim_to_dw(self, mock__append_dim_to_dw, closing):
        # arrange
        table_name = TestCRMTasksClosing.TABLE_NAMES['dim']

        # act
        closing.append_dim_to_dw()

        # assert
        assert mock__append_dim_to_dw.call_count == 1
        assert mock__append_dim_to_dw.call_args[1] == {'table_name': table_name}

    @mock.patch.object(CRMTasksClosing, '_delete_staging_entries')
    def test_delete_staging_fact_entries(self, mock__delete_staging_entries, closing):
        # arrange
        table_name = TestCRMTasksClosing.TABLE_NAMES['fact']

        # act
        closing.delete_staging_fact_entries()

        # assert
        assert mock__delete_staging_entries.call_count == 1
        assert mock__delete_staging_entries.call_args[1] == {'table_name': table_name}

    @mock.patch.object(CRMTasksClosing, '_delete_staging_entries')
    def test_delete_staging_dim_entries(self, mock__delete_staging_entries, closing):
        # arrange
        table_name = TestCRMTasksClosing.TABLE_NAMES['dim']

        # act
        closing.delete_staging_dim_entries()

        # assert
        assert mock__delete_staging_entries.call_count == 1
        assert mock__delete_staging_entries.call_args[1] == {'table_name': table_name}
