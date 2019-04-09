import mock

from bietlejuice.jobs.etl.crm.tasks import CRMTasksCollection


class TestCRMTasksCollection(object):
    MANUAL_TASK_WORKGROUP_IDS = [
        'DEP_COLLECTIONS_ID'
    ]

    TABLE_NAMES = {
        'fact': 'fact_collection_tasks',
        'dim': 'dim_collection_task'
    }

    QUERY_FILENAMES = {
        'staging': 'append_fact_collection_info.sql',
        'prod': 'append_fact_collection_table.sql'
    }

    @mock.patch.object(CRMTasksCollection, '_move_fact_to_staging')
    def test_move_fact_to_staging(self, mock__move_fact_to_staging, collection):
        # arrange
        table_name = TestCRMTasksCollection.TABLE_NAMES['fact']
        append_query_name = TestCRMTasksCollection.QUERY_FILENAMES['staging']
        manual_workgroup_ids = TestCRMTasksCollection.MANUAL_TASK_WORKGROUP_IDS

        # act
        collection.move_fact_to_staging()

        # assert
        assert mock__move_fact_to_staging.call_count == 1
        assert mock__move_fact_to_staging.call_args[1]['table_name'] == table_name
        assert mock__move_fact_to_staging.call_args[1]['append_query_filename'] == append_query_name
        assert mock__move_fact_to_staging.call_args[1]['manual_task_workgroups'] == manual_workgroup_ids

    @mock.patch.object(CRMTasksCollection, '_move_dim_to_staging')
    def test_move_dim_to_staging(self, mock__move_dim_to_staging, collection):
        # arrange
        table_name = TestCRMTasksCollection.TABLE_NAMES['dim']

        # act
        collection.move_dim_to_staging()

        # assert
        assert mock__move_dim_to_staging.call_count == 1
        assert mock__move_dim_to_staging.call_args[1]['table_name'] == table_name

    @mock.patch.object(CRMTasksCollection, '_append_fact_to_dw')
    def test_append_fact_to_dw(self, mock__append_fact_to_dw, collection):
        # arrange
        table_name = TestCRMTasksCollection.TABLE_NAMES['fact']
        append_query_name = TestCRMTasksCollection.QUERY_FILENAMES['prod']

        # act
        collection.append_fact_to_dw()

        # assert
        assert mock__append_fact_to_dw.call_count == 1
        assert mock__append_fact_to_dw.call_args[1]['table_name'] == table_name
        assert mock__append_fact_to_dw.call_args[1]['query_filename'] == append_query_name

    @mock.patch.object(CRMTasksCollection, '_append_dim_to_dw')
    def test_append_dim_to_dw(self, mock__append_dim_to_dw, collection):
        # arrange
        table_name = TestCRMTasksCollection.TABLE_NAMES['dim']

        # act
        collection.append_dim_to_dw()

        # assert
        assert mock__append_dim_to_dw.call_count == 1
        assert mock__append_dim_to_dw.call_args[1]['table_name'] == table_name

    @mock.patch.object(CRMTasksCollection, '_delete_staging_entries')
    def test_delete_staging_fact_entries(self, mock__delete_staging_entries, collection):
        # arrange
        table_name = TestCRMTasksCollection.TABLE_NAMES['fact']

        # act
        collection.delete_staging_fact_entries()

        # assert
        assert mock__delete_staging_entries.call_count == 1
        assert mock__delete_staging_entries.call_args[1]['table_name'] == table_name

    @mock.patch.object(CRMTasksCollection, '_delete_staging_entries')
    def test_delete_staging_dim_entries(self, mock__delete_staging_entries, collection):
        # arrange
        table_name = TestCRMTasksCollection.TABLE_NAMES['dim']

        # act
        collection.delete_staging_dim_entries()

        # assert
        assert mock__delete_staging_entries.call_count == 1
        assert mock__delete_staging_entries.call_args[1]['table_name'] == table_name
