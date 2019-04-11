from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.crm.tasks.tasks import CRMTasks

logger = QuintoAndarLogger('CRMTasksCollection')


class CRMTasksCollection(CRMTasks):
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

    # TODO remove mongo_client_uri from child classes
    @logger
    def __init__(self, s3_bucket, execution_date, mongo_client_uri=None):
        super(CRMTasksCollection, self).__init__(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @logger
    def move_fact_to_staging(self):
        self._move_fact_to_staging(
            table_name=CRMTasksCollection.TABLE_NAMES['fact'],
            manual_task_workgroups=CRMTasksCollection.MANUAL_TASK_WORKGROUP_IDS,
            append_query_filename=CRMTasksCollection.QUERY_FILENAMES['staging']
        )

    @logger
    def move_dim_to_staging(self):
        self._move_dim_to_staging(
            table_name=CRMTasksCollection.TABLE_NAMES['dim'],
            manual_task_workgroups=CRMTasksCollection.MANUAL_TASK_WORKGROUP_IDS
        )

    @logger
    def append_fact_to_dw(self):
        self._append_fact_to_dw(
            table_name=CRMTasksCollection.TABLE_NAMES['fact'],
            query_filename=CRMTasksCollection.QUERY_FILENAMES['prod']
        )

    @logger
    def append_dim_to_dw(self):
        self._append_dim_to_dw(table_name=CRMTasksCollection.TABLE_NAMES['dim'])

    @logger
    def delete_staging_fact_entries(self):
        self._delete_staging_entries(table_name=CRMTasksCollection.TABLE_NAMES['fact'])

    @logger
    def delete_staging_dim_entries(self):
        self._delete_staging_entries(table_name=CRMTasksCollection.TABLE_NAMES['dim'])
