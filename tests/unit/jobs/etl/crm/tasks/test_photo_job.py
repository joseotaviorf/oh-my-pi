import mock

from bietlejuice.jobs.etl.crm.tasks import CRMTasksPhotoJob


class TestCRMTasksPhotoJob(object):
    QUEUES = [
        'FupFoto',
        'AgendarJobDeFotografo'
    ]

    TABLE_NAMES = {
        'fact': 'fact_photo_job_tasks',
        'dim': 'dim_photo_job_task'
    }

    QUERY_FILENAMES = {
        'staging': 'append_fact_photo_job_info.sql',
        'prod': 'append_fact_photo_job_table.sql'
    }

    @mock.patch.object(CRMTasksPhotoJob, '_move_fact_to_staging')
    def test_move_fact_to_staging(self, mock__move_fact_to_staging, photo_job):
        # arrange
        table_name = TestCRMTasksPhotoJob.TABLE_NAMES['fact']
        queues = TestCRMTasksPhotoJob.QUEUES
        append_query_filename = TestCRMTasksPhotoJob.QUERY_FILENAMES['staging']

        # act
        photo_job.move_fact_to_staging()

        # assert
        assert mock__move_fact_to_staging.call_count == 1
        assert mock__move_fact_to_staging.call_args[1] == {
            'table_name': table_name,
            'queues': queues,
            'append_query_filename': append_query_filename
        }

    @mock.patch.object(CRMTasksPhotoJob, '_move_dim_to_staging')
    def test_move_dim_to_staging(self, mock__move_dim_to_staging, photo_job):
        # arrange
        table_name = TestCRMTasksPhotoJob.TABLE_NAMES['dim']
        queues = TestCRMTasksPhotoJob.QUEUES

        # act
        photo_job.move_dim_to_staging()

        # assert
        assert mock__move_dim_to_staging.call_count == 1
        assert mock__move_dim_to_staging.call_args[1] == {
            'table_name': table_name,
            'queues': queues
        }

    @mock.patch.object(CRMTasksPhotoJob, '_append_fact_to_dw')
    def test_append_fact_to_dw(self, mock__append_fact_to_dw, photo_job):
        # arrange
        table_name = TestCRMTasksPhotoJob.TABLE_NAMES['fact']
        query_filename = TestCRMTasksPhotoJob.QUERY_FILENAMES['prod']

        # act
        photo_job.append_fact_to_dw()

        # assert
        assert mock__append_fact_to_dw.call_count == 1
        assert mock__append_fact_to_dw.call_args[1] == {
            'table_name': table_name,
            'query_filename': query_filename
        }

    @mock.patch.object(CRMTasksPhotoJob, '_append_dim_to_dw')
    def test_append_dim_to_dw(self, mock__append_dim_to_dw, photo_job):
        # arrange
        table_name = TestCRMTasksPhotoJob.TABLE_NAMES['dim']

        # act
        photo_job.append_dim_to_dw()

        # assert
        assert mock__append_dim_to_dw.call_count == 1
        assert mock__append_dim_to_dw.call_args[1] == {'table_name': table_name}

    @mock.patch.object(CRMTasksPhotoJob, '_delete_staging_entries')
    def test_delete_staging_fact_entries(self, mock__delete_staging_entries, photo_job):
        # arrange
        table_name = TestCRMTasksPhotoJob.TABLE_NAMES['fact']

        # act
        photo_job.delete_staging_fact_entries()

        # assert
        assert mock__delete_staging_entries.call_count == 1
        assert mock__delete_staging_entries.call_args[1] == {'table_name': table_name}

    @mock.patch.object(CRMTasksPhotoJob, '_delete_staging_entries')
    def test_delete_staging_dim_entries(self, mock__delete_staging_entries, photo_job):
        # arrange
        table_name = TestCRMTasksPhotoJob.TABLE_NAMES['dim']

        # act
        photo_job.delete_staging_dim_entries()

        # assert
        assert mock__delete_staging_entries.call_count == 1
        assert mock__delete_staging_entries.call_args[1] == {'table_name': table_name}
