from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.new_etl.crm.tasks.tasks import CRMTasks

logger = QuintoAndarLogger('CRMTasksPhotoJob')


class CRMTasksPhotoJob(CRMTasks):
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

    @logger(exclude='mongo_client_uri')
    def __init__(self, s3_bucket, mongo_client_uri, execution_date):
        super(CRMTasksPhotoJob, self).__init__(
            s3_bucket=s3_bucket,
            mongo_client_uri=mongo_client_uri,
            execution_date=execution_date
        )

    @logger
    def move_fact_to_staging(self):
        self._move_fact_to_staging(
            table_name=CRMTasksPhotoJob.TABLE_NAMES['fact'],
            queues=CRMTasksPhotoJob.QUEUES,
            append_query_filename=CRMTasksPhotoJob.QUERY_FILENAMES['staging']
        )

    @logger
    def move_dim_to_staging(self):
        self._move_dim_to_staging(
            table_name=CRMTasksPhotoJob.TABLE_NAMES['dim'],
            queues=CRMTasksPhotoJob.QUEUES
        )

    @logger
    def append_fact_to_dw(self):
        self._append_fact_to_dw(
            table_name=CRMTasksPhotoJob.TABLE_NAMES['fact'],
            query_filename=CRMTasksPhotoJob.QUERY_FILENAMES['prod']
        )

    @logger
    def append_dim_to_dw(self):
        self._append_dim_to_dw(table_name=CRMTasksPhotoJob.TABLE_NAMES['dim'])

    @logger
    def delete_staging_fact_entries(self):
        self._delete_staging_entries(table_name=CRMTasksPhotoJob.TABLE_NAMES['fact'])

    @logger
    def delete_staging_dim_entries(self):
        self._delete_staging_entries(table_name=CRMTasksPhotoJob.TABLE_NAMES['dim'])
