import mock
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.new_base_etl import BaseETL
from bietlejuice.jobs.etl.crm.tasks import CRMTasks


class TestCRMTasks(object):

    @mock.patch.object(BaseETL, 'get_query_from_file_name', return_value='select 1 from dummy where __WHERE_CLAUSE__')
    @mock.patch.object(CRMTasks, '_is_prod_table_empty', return_value=True)
    @mock.patch.object(AthenaClient, 'execute_query_and_return_dataframe')
    @mock.patch.object(BaseETL, 'dataframe_to_db')
    def test__move_to_staging_without_queues_and_manual_task_workgroups(self, mock_dataframe_to_db,
                                                                        mock_execute_query_and_return_dataframe,
                                                                        mock__is_prod_table_empty,
                                                                        mock_get_query_from_file_name, tasks):
        # arrange
        final_query = """select 1 from dummy where (trim(ct.type) = 'Manual' and ct.metadata not like '%workgroupId%')"""
        table_name = 'table_name'
        queues = None
        query_filename = None
        manual_task_workgroups = None
        append_query_filename = None

        # act
        tasks._move_to_staging(
            table_name=table_name,
            queues=queues,
            query_filename=query_filename,
            manual_task_workgroups=manual_task_workgroups,
            append_query_filename=append_query_filename
        )

        # assert
        assert mock_get_query_from_file_name.call_count == 1
        assert mock__is_prod_table_empty.call_count == 1
        assert mock_dataframe_to_db.call_count == 1
        assert mock_execute_query_and_return_dataframe.call_count == 1
        assert mock_execute_query_and_return_dataframe.call_args[0][0] == final_query
