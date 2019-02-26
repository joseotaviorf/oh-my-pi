import mock

from bietlejuice.jobs.etl.crm.tasks import CRMTasksRepair


class TestCRMTasksRepair(object):
    MANUAL_TASK_WORKGROUP_IDS = ['DEP_MEDIACAO_POS_CONTRATO_ID']

    TABLE_NAMES = {
        'fact': 'fact_repair_tasks',
        'dim': 'dim_repair_task'
    }

    QUERY_FILENAMES = {
        'staging': 'append_fact_repair_info.sql',
        'prod': 'append_fact_repair_table.sql'
    }

    @mock.patch.object(CRMTasksRepair, '_move_fact_to_staging')
    def test_move_fact_to_staging(self, mock__move_fact_to_staging, repair):
        # arrange
        table_name = TestCRMTasksRepair.TABLE_NAMES['fact']
        manual_task_workgroups = TestCRMTasksRepair.MANUAL_TASK_WORKGROUP_IDS
        append_query_filename = TestCRMTasksRepair.QUERY_FILENAMES['staging']

        # act
        repair.move_fact_to_staging()

        # assert
        assert mock__move_fact_to_staging.call_count == 1
        assert mock__move_fact_to_staging.call_args[1] == {
            'table_name': table_name,
            'manual_task_workgroups': manual_task_workgroups,
            'append_query_filename': append_query_filename
        }

    @mock.patch.object(CRMTasksRepair, '_move_dim_to_staging')
    def test_move_dim_to_staging(self, mock__move_dim_to_staging, repair):
        # arrange
        table_name = TestCRMTasksRepair.TABLE_NAMES['dim']
        manual_task_workgroups = TestCRMTasksRepair.MANUAL_TASK_WORKGROUP_IDS

        # act
        repair.move_dim_to_staging()

        # assert
        assert mock__move_dim_to_staging.call_count == 1
        assert mock__move_dim_to_staging.call_args[1] == {
            'table_name': table_name,
            'manual_task_workgroups': manual_task_workgroups
        }

    @mock.patch.object(CRMTasksRepair, '_append_fact_to_dw')
    def test_append_fact_to_dw(self, mock__append_fact_to_dw, repair):
        # arrange
        table_name = TestCRMTasksRepair.TABLE_NAMES['fact']
        query_filename = TestCRMTasksRepair.QUERY_FILENAMES['prod']

        # act
        repair.append_fact_to_dw()

        # assert
        assert mock__append_fact_to_dw.call_count == 1
        assert mock__append_fact_to_dw.call_args[1] == {
            'table_name': table_name,
            'query_filename': query_filename
        }

    @mock.patch.object(CRMTasksRepair, '_append_dim_to_dw')
    def test_append_dim_to_dw(self, mock__append_dim_to_dw, repair):
        # arrange
        table_name = TestCRMTasksRepair.TABLE_NAMES['dim']

        # act
        repair.append_dim_to_dw()

        # assert
        assert mock__append_dim_to_dw.call_count == 1
        assert mock__append_dim_to_dw.call_args[1] == {'table_name': table_name}

    @mock.patch.object(CRMTasksRepair, '_delete_staging_entries')
    def test_delete_staging_fact_entries(self, mock__delete_staging_entries, repair):
        # arrange
        table_name = TestCRMTasksRepair.TABLE_NAMES['fact']

        # act
        repair.delete_staging_fact_entries()

        # assert
        assert mock__delete_staging_entries.call_count == 1
        assert mock__delete_staging_entries.call_args[1] == {'table_name': table_name}

    @mock.patch.object(CRMTasksRepair, '_delete_staging_entries')
    def test_delete_staging_dim_entries(self, mock__delete_staging_entries, repair):
        # arrange
        table_name = TestCRMTasksRepair.TABLE_NAMES['dim']

        # act
        repair.delete_staging_dim_entries()

        # assert
        assert mock__delete_staging_entries.call_count == 1
        assert mock__delete_staging_entries.call_args[1] == {'table_name': table_name}
