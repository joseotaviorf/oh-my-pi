import mock

from bietlejuice.jobs.etl.crm.tasks import CRMTasksLead


class TestCRMTasksLead(object):
    QUEUES = [
        'ConverterLead',
        'ConverterLeadPrioritario'
    ]

    TABLE_NAMES = {
        'fact': 'fact_lead_tasks',
        'dim': 'dim_lead_task'
    }

    QUERY_FILENAMES = {
        'staging': 'append_fact_lead_info.sql',
        'prod': 'append_fact_lead_table.sql'
    }

    @mock.patch.object(CRMTasksLead, '_move_fact_to_staging')
    def test_move_fact_to_staging(self, mock__move_fact_to_staging, lead):
        # arrange
        table_name = TestCRMTasksLead.TABLE_NAMES['fact']
        queues = TestCRMTasksLead.QUEUES
        append_query_filename = TestCRMTasksLead.QUERY_FILENAMES['staging']

        # act
        lead.move_fact_to_staging()

        # assert
        assert mock__move_fact_to_staging.call_count == 1
        assert mock__move_fact_to_staging.call_args[1] == {
            'table_name': table_name,
            'queues': queues,
            'append_query_filename': append_query_filename
        }

    @mock.patch.object(CRMTasksLead, '_move_dim_to_staging')
    def test_move_dim_to_staging(self, mock__move_dim_to_staging, lead):
        # arrange
        table_name = TestCRMTasksLead.TABLE_NAMES['dim']
        queues = TestCRMTasksLead.QUEUES

        # act
        lead.move_dim_to_staging()

        # assert
        assert mock__move_dim_to_staging.call_count == 1
        assert mock__move_dim_to_staging.call_args[1] == {
            'table_name': table_name,
            'queues': queues
        }

    @mock.patch.object(CRMTasksLead, '_append_fact_to_dw')
    def test_append_fact_to_dw(self, mock__append_fact_to_dw, lead):
        # arrange
        table_name = TestCRMTasksLead.TABLE_NAMES['fact']
        query_filename = TestCRMTasksLead.QUERY_FILENAMES['prod']

        # act
        lead.append_fact_to_dw()

        # assert
        assert mock__append_fact_to_dw.call_count == 1
        assert mock__append_fact_to_dw.call_args[1] == {
            'table_name': table_name,
            'query_filename': query_filename
        }

    @mock.patch.object(CRMTasksLead, '_append_dim_to_dw')
    def test_append_dim_to_dw(self, mock__append_dim_to_dw, lead):
        # arrange
        table_name = TestCRMTasksLead.TABLE_NAMES['dim']

        # act
        lead.append_dim_to_dw()

        # assert
        assert mock__append_dim_to_dw.call_count == 1
        assert mock__append_dim_to_dw.call_args[1] == {'table_name': table_name}

    @mock.patch.object(CRMTasksLead, '_delete_staging_entries')
    def test_delete_staging_fact_entries(self, mock__delete_staging_entries, lead):
        # arrange
        table_name = TestCRMTasksLead.TABLE_NAMES['fact']

        # act
        lead.delete_staging_fact_entries()

        # assert
        assert mock__delete_staging_entries.call_count == 1
        assert mock__delete_staging_entries.call_args[1] == {'table_name': table_name}

    @mock.patch.object(CRMTasksLead, '_delete_staging_entries')
    def test_delete_staging_dim_entries(self, mock__delete_staging_entries, lead):
        # arrange
        table_name = TestCRMTasksLead.TABLE_NAMES['dim']

        # act
        lead.delete_staging_dim_entries()

        # assert
        assert mock__delete_staging_entries.call_count == 1
        assert mock__delete_staging_entries.call_args[1] == {'table_name': table_name}
