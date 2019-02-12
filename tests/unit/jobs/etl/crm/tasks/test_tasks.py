from datetime import datetime

import boto3
import mock
import pytest
from mock import Mock
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

    @mock.patch.object(CRMTasks, '_get_mongo_client')
    def test_init_with_mongo_uri(self, mock_get_mongo_client):
        # arrange
        s3_bucket = mock.ANY
        mongo_client_uri = mock.ANY
        execution_date = Mock(datetime)

        # act
        tasks = CRMTasks(
            s3_bucket=s3_bucket,
            mongo_client_uri=mongo_client_uri,
            execution_date=execution_date
        )

        # assert
        assert tasks.mongo_client is not None
        assert mock_get_mongo_client.call_count == 1
        assert mock_get_mongo_client.call_args[0][0] == mongo_client_uri

    @mock.patch.object(CRMTasks, '_get_mongo_client')
    def test_init_without_mongo_uri(self, mock_get_mongo_client):
        # arrange
        s3_bucket = mock.ANY
        execution_date = Mock(datetime)

        # act
        tasks = CRMTasks(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

        # assert
        assert tasks.mongo_client is not None
        assert mock_get_mongo_client.call_count == 1
        assert mock_get_mongo_client.call_args[0][0] is None

    def test_data_existence_check_with_invalid_bucket_type(self, tasks):
        # arrange
        bucket_type = 'bucket_type'

        # act & assert
        with pytest.raises(ValueError):
            tasks.data_existence_check(bucket_type=bucket_type)

    @mock.patch.object(boto3, 'resource')
    def test_data_existence(self, mock_resource, tasks):
        # arrange
        bucket_type = 'raw'
        partition_date = tasks.partition_date
        s3_bucket = 's3_bucket'
        crm_bucket_suffix = tasks.BUCKET_FOLDER_SUFFIXES['tasks']
        s3_file_name = tasks.S3_FILE_NAME
        file_path = '{}/{}/dt={}/{}.gz'.format(bucket_type,
                                               crm_bucket_suffix,
                                               partition_date,
                                               s3_file_name)
        s3_resource = mock_resource('s3')
        tasks.s3_resource = s3_resource

        # act
        result = tasks.data_existence_check(bucket_type=bucket_type)

        assert tasks.s3_resource.Object.call_count == 1
        assert tasks.s3_resource.Object.call_args[0] == (s3_bucket, file_path)
        assert tasks.s3_resource.Object(s3_bucket, file_path).load.call_count == 1
        assert result is True
