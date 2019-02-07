import mock

from bietlejuice.jobs.etl.crm.tasks import CRMTasksCredit


class TestCRMTasksCredit(object):
    QUEUES = [
        'EnviarCardiff',
        'AnalisarDocumentacaoProprietario'
    ]

    TABLE_NAMES = {
        'fact': 'fact_credit_tasks',
        'dim': 'dim_credit_task'
    }

    QUERY_FILENAMES = {
        'staging': 'append_fact_credit_info.sql',
        'prod': 'append_fact_credit_table.sql'
    }

    @mock.patch.object(CRMTasksCredit, '_move_fact_to_staging')
    def test_move_fact_to_staging(self, mock__move_fact_to_staging, credit):
        # arrange
        table_name = TestCRMTasksCredit.TABLE_NAMES['fact']
        queues = TestCRMTasksCredit.QUEUES
        append_query_filename = TestCRMTasksCredit.QUERY_FILENAMES['staging']

        # act
        credit.move_fact_to_staging()

        # assert
        assert mock__move_fact_to_staging.call_count == 1
        assert mock__move_fact_to_staging.call_args[1] == {
            'table_name': table_name,
            'queues': queues,
            'append_query_filename': append_query_filename
        }

    @mock.patch.object(CRMTasksCredit, '_move_dim_to_staging')
    def test_move_dim_to_staging(self, mock__move_dim_to_staging, credit):
        # arrange
        table_name = TestCRMTasksCredit.TABLE_NAMES['dim']
        queues = TestCRMTasksCredit.QUEUES

        # act
        credit.move_dim_to_staging()

        # assert
        assert mock__move_dim_to_staging.call_count == 1
        assert mock__move_dim_to_staging.call_args[1] == {
            'table_name': table_name,
            'queues': queues
        }

    @mock.patch.object(CRMTasksCredit, '_append_fact_to_dw')
    def test_append_fact_to_dw(self, mock__append_fact_to_dw, credit):
        # arrange
        table_name = TestCRMTasksCredit.TABLE_NAMES['fact']
        query_filename = TestCRMTasksCredit.QUERY_FILENAMES['prod']

        # act
        credit.append_fact_to_dw()

        # assert
        assert mock__append_fact_to_dw.call_count == 1
        assert mock__append_fact_to_dw.call_args[1] == {
            'table_name': table_name,
            'query_filename': query_filename
        }

    @mock.patch.object(CRMTasksCredit, '_append_dim_to_dw')
    def test_append_dim_to_dw(self, mock__append_dim_to_dw, credit):
        # arrange
        table_name = TestCRMTasksCredit.TABLE_NAMES['dim']

        # act
        credit.append_dim_to_dw()

        # assert
        assert mock__append_dim_to_dw.call_count == 1
        assert mock__append_dim_to_dw.call_args[1] == {'table_name': table_name}

    @mock.patch.object(CRMTasksCredit, '_delete_staging_entries')
    def test_delete_staging_fact_entries(self, mock__delete_staging_entries, credit):
        # arrange
        table_name = TestCRMTasksCredit.TABLE_NAMES['fact']

        # act
        credit.delete_staging_fact_entries()

        # assert
        assert mock__delete_staging_entries.call_count == 1
        assert mock__delete_staging_entries.call_args[1] == {'table_name': table_name}

    @mock.patch.object(CRMTasksCredit, '_delete_staging_entries')
    def test_delete_staging_dim_entries(self, mock__delete_staging_entries, credit):
        # arrange
        table_name = TestCRMTasksCredit.TABLE_NAMES['dim']

        # act
        credit.delete_staging_dim_entries()

        # assert
        assert mock__delete_staging_entries.call_count == 1
        assert mock__delete_staging_entries.call_args[1] == {'table_name': table_name}
