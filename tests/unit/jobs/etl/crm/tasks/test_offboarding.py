import mock

from bietlejuice.jobs.etl.crm.tasks import CRMTasksOffboarding


class TestCRMTasksOffboarding(object):
    MANUAL_TASK_WORKGROUP_IDS = [
        'DEP_OFFBOARDING_2',
        'DEP_OFFBOARDING_ID',
        'DEP_VISTORIA_OFFBOARDING'
    ]

    TABLE_NAMES = {
        'fact': 'fact_offboarding_tasks',
        'dim': 'dim_offboarding_task'
    }

    QUERY_FILENAMES = {
        'staging': 'append_fact_offboarding_info.sql',
        'prod': 'append_fact_offboarding_table.sql'
    }

    @mock.patch.object(CRMTasksOffboarding, '_move_fact_to_staging')
    def test_move_fact_to_staging(self, mock__move_fact_to_staging, offboarding):
        # arrange
        table_name = TestCRMTasksOffboarding.TABLE_NAMES['fact']
        append_query_name = TestCRMTasksOffboarding.QUERY_FILENAMES['staging']
        manual_workgroup_ids = TestCRMTasksOffboarding.MANUAL_TASK_WORKGROUP_IDS

        # act
        offboarding.move_fact_to_staging()

        # assert
        assert mock__move_fact_to_staging.call_count == 1
        assert mock__move_fact_to_staging.call_args[1]['table_name'] == table_name
        assert mock__move_fact_to_staging.call_args[1]['append_query_filename'] == append_query_name
        assert mock__move_fact_to_staging.call_args[1]['manual_task_workgroups'] == manual_workgroup_ids

    @mock.patch.object(CRMTasksOffboarding, '_move_dim_to_staging')
    def test_move_dim_to_staging(self, mock__move_dim_to_staging, offboarding):
        # arrange
        table_name = TestCRMTasksOffboarding.TABLE_NAMES['dim']

        # act
        offboarding.move_dim_to_staging()

        # assert
        assert mock__move_dim_to_staging.call_count == 1
        assert mock__move_dim_to_staging.call_args[1]['table_name'] == table_name

    @mock.patch.object(CRMTasksOffboarding, '_append_fact_to_dw')
    def test_append_fact_to_dw(self, mock__append_fact_to_dw, offboarding):
        # arrange
        table_name = TestCRMTasksOffboarding.TABLE_NAMES['fact']
        append_query_name = TestCRMTasksOffboarding.QUERY_FILENAMES['prod']

        # act
        offboarding.append_fact_to_dw()

        # assert
        assert mock__append_fact_to_dw.call_count == 1
        assert mock__append_fact_to_dw.call_args[1]['table_name'] == table_name
        assert mock__append_fact_to_dw.call_args[1]['query_filename'] == append_query_name

    @mock.patch.object(CRMTasksOffboarding, '_append_dim_to_dw')
    def test_append_dim_to_dw(self, mock__append_dim_to_dw, offboarding):
        # arrange
        table_name = TestCRMTasksOffboarding.TABLE_NAMES['dim']

        # act
        offboarding.append_dim_to_dw()

        # assert
        assert mock__append_dim_to_dw.call_count == 1
        assert mock__append_dim_to_dw.call_args[1]['table_name'] == table_name

    @mock.patch.object(CRMTasksOffboarding, '_delete_staging_entries')
    def test_delete_staging_fact_entries(self, mock__delete_staging_entries, offboarding):
        # arrange
        table_name = TestCRMTasksOffboarding.TABLE_NAMES['fact']

        # act
        offboarding.delete_staging_fact_entries()

        # assert
        assert mock__delete_staging_entries.call_count == 1
        assert mock__delete_staging_entries.call_args[1]['table_name'] == table_name

    @mock.patch.object(CRMTasksOffboarding, '_delete_staging_entries')
    def test_delete_staging_dim_entries(self, mock__delete_staging_entries, offboarding):
        # arrange
        table_name = TestCRMTasksOffboarding.TABLE_NAMES['dim']

        # act
        offboarding.delete_staging_dim_entries()

        # assert
        assert mock__delete_staging_entries.call_count == 1
        assert mock__delete_staging_entries.call_args[1]['table_name'] == table_name
