import re
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
    @mock.patch.object(CRMTasks, '_is_table_empty', return_value=True)
    @mock.patch.object(AthenaClient, 'execute_query_and_return_dataframe')
    @mock.patch.object(BaseETL, 'dataframe_to_db')
    def test__move_to_staging_without_queues_and_manual_task_workgroups(self, mock_dataframe_to_db,
                                                                        mock_execute_query_and_return_dataframe,
                                                                        mock__is_table_empty,
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
        assert mock__is_table_empty.call_count == 1
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

    @mock.patch.object(BaseETL, 'from_db_query')
    @pytest.mark.parametrize('from_db_return, expected', [([], False), ([1], True)])
    def test__is_table_empty_false(self, mock_from_db_query, tasks, from_db_return, expected):
        # arrange
        mock_from_db_query.return_value = from_db_return

        # act
        result = tasks._is_table_empty(
            schema=mock.ANY,
            table_name=mock.ANY
        )

        # assert
        assert result == expected

    @mock.patch.object(CRMTasks, '_move_to_clean')
    def test_move_tasks_resolution_to_clean(self, mock__move_to_clean, tasks):
        # act
        tasks.move_tasks_resolution_to_clean()

        # assert
        for _, value in mock__move_to_clean.call_args[1]['r_cols'].items():
            assert value == str

    @mock.patch.object(CRMTasks, '_move_to_clean')
    def test_move_tasks_to_clean(self, mock__move_to_clean, tasks):
        # act
        tasks.move_tasks_to_clean()

        # assert
        for _, value in mock__move_to_clean.call_args[1]['r_cols'].items():
            assert value == str

    def test__upsert_partition_invalid_bucket_type(self, tasks):
        # arrange
        bucket_type = 'invalid'

        # act & assert
        with pytest.raises(ValueError):
            tasks._upsert_partition(bucket_type, mock.ANY, mock.ANY)

    @mock.patch.object(BaseETL, 'obj_to_s3')
    def test__save_to_s3(self, mock_obj_to_s3, tasks):
        # arrange
        json_list = iter([{'field': 'value'}])
        total_count = 1

        # act
        tasks._save_to_s3(json_list, total_count)

        # assert
        assert re.match('raw\/[^\/]+\/[^\/]+\/dt=[^\/]+\/[^\.]+\.gz', mock_obj_to_s3.call_args[1]['file_path'])

    @pytest.mark.parametrize('json_list, total_count',
                             [(None, mock.ANY), (iter([{'field': 'value'}]), 0)])
    def test__save_to_s3_no_results(self, tasks, json_list, total_count):
        # act
        result = tasks._save_to_s3(json_list, total_count)

        # assert
        assert result is None

    @mock.patch.object(AthenaClient, 'create_parquet_from_query')
    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    def test__move_to_clean(self,
                            mock_get_query_from_file_name,
                            mock_create_parquet_from_query,
                            tasks):
        # act
        tasks._move_to_clean(mock.ANY, mock.ANY, mock.ANY, mock.ANY)

        # assert
        assert re.match('clean\/[^\/]+\/dt=[^\/]+\/[^\.]+\.parq',
                        mock_create_parquet_from_query.call_args[1]['key'])

    @mock.patch.object(BaseETL, 'get_query_from_file_name', return_value='__WHERE_CLAUSE__')
    @mock.patch.object(CRMTasks, '_is_table_empty', return_value=True)
    @mock.patch.object(AthenaClient, 'execute_query_and_return_dataframe')
    @mock.patch.object(BaseETL, 'dataframe_to_db')
    @pytest.mark.parametrize('table_empty, queues, manual_task_workgroups, append_query_filename, final_query_expected',
                             [(True, None, ['w0'], None,
                               '(trim(ct.type) = \'Manual\' and regexp_extract(ct.metadata, \'workgroupId":"([^"]+)\', 1) in (\'w0\'))'),
                              (True, None, None, None,
                               '(trim(ct.type) = \'Manual\' and ct.metadata not like \'%workgroupId%\')'),
                              (True, ['q0'], ['w0'], None,
                               '(trim(ct.type) in (\'q0\') or (trim(ct.type) = \'Manual\' and regexp_extract(ct.metadata, \'workgroupId":"([^"]+)\', 1) in (\'w0\')))'),
                              (True, ['q0'], None, None,
                               'trim(ct.type) in (\'q0\')'),
                              (True, ['q0'], None, 'append',
                               'trim(ct.type) in (\'q0\')\n__WHERE_CLAUSE__'),
                              (False, ['q0'], None, None,
                               'trim(ct.type) in (\'q0\') and dt = \'2019-01-02\'')])
    def test__move_to_staging(self,
                              mock_dataframe_to_db,
                              mock_execute_query_and_return_dataframe,
                              mock__is_table_empty,
                              mock_get_query_from_file_name,
                              tasks,
                              table_empty,
                              queues,
                              manual_task_workgroups,
                              append_query_filename,
                              final_query_expected):
        # arrange
        mock__is_table_empty.return_value = table_empty

        # act
        tasks._move_to_staging(
            mock.ANY,
            queues,
            mock.ANY,
            manual_task_workgroups,
            append_query_filename
        )

        # assert
        assert mock_execute_query_and_return_dataframe.call_args[0][0] == final_query_expected
