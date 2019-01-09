import mock

from bietlejuice.jobs.etl.crm.tasks import CRMTasksUngroupedManual


class TestCRMTasksUngroupedManual(object):
    TABLE_NAMES = {
        'fact': 'fact_ungrouped_manual_tasks',
        'dim': 'dim_ungrouped_manual_task'
    }

    @mock.patch.object(CRMTasksUngroupedManual, '_move_fact_to_staging')
    def test_move_fact_to_staging(self, mock__move_fact_to_staging, ungrouped_manual):
        # arrange
        table_name = TestCRMTasksUngroupedManual.TABLE_NAMES['fact']

        # act
        ungrouped_manual.move_fact_to_staging()

        # assert
        assert mock__move_fact_to_staging.call_count == 1
        assert mock__move_fact_to_staging.call_args[1] == {'table_name': table_name}

    @mock.patch.object(CRMTasksUngroupedManual, '_move_dim_to_staging')
    def test_move_dim_to_staging(self, mock__move_dim_to_staging, ungrouped_manual):
        # arrange
        table_name = TestCRMTasksUngroupedManual.TABLE_NAMES['dim']

        # act
        ungrouped_manual.move_dim_to_staging()

        # assert
        assert mock__move_dim_to_staging.call_count == 1
        assert mock__move_dim_to_staging.call_args[1] == {'table_name': table_name}

    @mock.patch.object(CRMTasksUngroupedManual, '_append_fact_to_dw')
    def test_append_fact_to_dw(self, mock__append_fact_to_dw, ungrouped_manual):
        # arrange
        table_name = TestCRMTasksUngroupedManual.TABLE_NAMES['fact']

        # act
        ungrouped_manual.append_fact_to_dw()

        # assert
        assert mock__append_fact_to_dw.call_count == 1
        assert mock__append_fact_to_dw.call_args[1] == {'table_name': table_name}

    @mock.patch.object(CRMTasksUngroupedManual, '_append_dim_to_dw')
    def test_append_dim_to_dw(self, mock__append_dim_to_dw, ungrouped_manual):
        # arrange
        table_name = TestCRMTasksUngroupedManual.TABLE_NAMES['dim']

        # act
        ungrouped_manual.append_dim_to_dw()

        # assert
        assert mock__append_dim_to_dw.call_count == 1
        assert mock__append_dim_to_dw.call_args[1] == {'table_name': table_name}

    @mock.patch.object(CRMTasksUngroupedManual, '_delete_staging_entries')
    def test_delete_staging_fact_entries(self, mock__delete_staging_entries, ungrouped_manual):
        # arrange
        table_name = TestCRMTasksUngroupedManual.TABLE_NAMES['fact']

        # act
        ungrouped_manual.delete_staging_fact_entries()

        # assert
        assert mock__delete_staging_entries.call_count == 1
        assert mock__delete_staging_entries.call_args[1] == {'table_name': table_name}

    @mock.patch.object(CRMTasksUngroupedManual, '_delete_staging_entries')
    def test_delete_staging_dim_entries(self, mock__delete_staging_entries, ungrouped_manual):
        # arrange
        table_name = TestCRMTasksUngroupedManual.TABLE_NAMES['dim']

        # act
        ungrouped_manual.delete_staging_dim_entries()

        # assert
        assert mock__delete_staging_entries.call_count == 1
        assert mock__delete_staging_entries.call_args[1] == {'table_name': table_name}
