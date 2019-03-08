from collections import OrderedDict
from copy import deepcopy

import boto3
import mock
import petl
import pytest
from botocore.exceptions import ClientError
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR, SOURCE_QUERIES_DIR
from bietlejuice.jobs.etl.asterisk import AsteriskTableEnum


class TestAsterisk(object):

    @pytest.mark.parametrize('bucket_type', ['raw', 'clean'])
    @mock.patch.object(boto3, 'resource')
    def test__data_existence_check_partitioned_successfully(self, mock_resource, bucket_type, asterisk):
        # arrange
        class_ = AsteriskTableEnum.CDR
        file_path = '{}/asterisk/{}/dt={}/data.gz'.format(bucket_type, class_.value, asterisk.partition_date)
        s3_bucket = asterisk.s3_bucket
        asterisk.s3_resource = mock_resource('s3')
        expected = True

        # act
        result = asterisk._data_existence_check_partitioned(bucket_type, class_)

        # assert
        asterisk.s3_resource.Object.assert_called_once_with(s3_bucket, file_path)
        assert result == expected

    @mock.patch.object(boto3, 'resource')
    def test__data_existence_check_partitioned_invalid_path(self, mock_resource, asterisk):
        # arrange
        bucket_type = mock.ANY
        class_ = AsteriskTableEnum.CDR
        file_path = mock.ANY
        s3_bucket = mock.ANY
        asterisk.s3_resource = mock_resource('s3')
        asterisk.s3_resource.Object(s3_bucket, file_path).load.side_effect = ClientError(
            error_response={'Error': {'Message': 'Not Found', 'Code': '404'}},
            operation_name='HeadObject')
        expected = False

        # act & assert
        result = asterisk._data_existence_check_partitioned(bucket_type, class_)

        # assert
        assert result == expected

    @mock.patch.object(boto3, 'resource')
    def test__data_existence_check_partitioned_error_s3(self, mock_resource, asterisk):
        # arrange
        bucket_type = mock.ANY
        class_ = AsteriskTableEnum.CDR
        file_path = mock.ANY
        s3_bucket = mock.ANY
        asterisk.s3_resource = mock_resource('s3')
        asterisk.s3_resource.Object(s3_bucket, file_path).load.side_effect = ClientError(
            error_response={'Error': {'Message': 'Internal Error', 'Code': '500'}},
            operation_name='HeadObject')

        # act & assert
        with pytest.raises(ClientError):
            asterisk._data_existence_check_partitioned(bucket_type, class_)

    def test__data_existence_check_partitioned_invalid_bucket(self, asterisk):
        # arrange
        bucket_type = 'dummy'
        class_ = AsteriskTableEnum.CDR

        # act & assert
        with pytest.raises(ValueError):
            asterisk._data_existence_check_partitioned(bucket_type, class_)

    @pytest.mark.parametrize('bucket_type', ['raw', 'clean'])
    @mock.patch.object(boto3, 'resource')
    def test__data_existence_check_full_successfully(self, mock_resource, bucket_type, asterisk):
        # arrange
        class_ = AsteriskTableEnum.CDR
        file_path = '{}/asterisk/{}/data.gz'.format(bucket_type, class_.value)
        s3_bucket = asterisk.s3_bucket
        asterisk.s3_resource = mock_resource('s3')
        expected = True

        # act
        result = asterisk._data_existence_check_full(bucket_type, class_)

        # assert
        asterisk.s3_resource.Object.assert_called_once_with(s3_bucket, file_path)
        assert result == expected

    @mock.patch.object(boto3, 'resource')
    def test__data_existence_check_full_invalid_path(self, mock_resource, asterisk):
        # arrange
        bucket_type = mock.ANY
        class_ = AsteriskTableEnum.CDR
        file_path = mock.ANY
        s3_bucket = mock.ANY
        asterisk.s3_resource = mock_resource('s3')
        asterisk.s3_resource.Object(s3_bucket, file_path).load.side_effect = ClientError(
            error_response={'Error': {'Message': 'Not Found', 'Code': '404'}},
            operation_name='HeadObject')
        expected = False

        # act & assert
        result = asterisk._data_existence_check_full(bucket_type, class_)

        # assert
        assert result == expected

    @mock.patch.object(boto3, 'resource')
    def test__data_existence_check_full_error_s3(self, mock_resource, asterisk):
        # arrange
        bucket_type = mock.ANY
        class_ = AsteriskTableEnum.CDR
        file_path = mock.ANY
        s3_bucket = mock.ANY
        asterisk.s3_resource = mock_resource('s3')
        asterisk.s3_resource.Object(s3_bucket, file_path).load.side_effect = ClientError(
            error_response={'Error': {'Message': 'Internal Error', 'Code': '500'}},
            operation_name='HeadObject')

        # act & assert
        with pytest.raises(ClientError):
            asterisk._data_existence_check_full(bucket_type, class_)

    def test__data_existence_check_full_invalid_bucket(self, asterisk):
        # arrange
        bucket_type = 'dummy'
        class_ = AsteriskTableEnum.CDR

        # act & assert
        with pytest.raises(ValueError):
            asterisk._data_existence_check_full(bucket_type, class_)

    @mock.patch.object(BaseETL, 'obj_to_s3')
    @mock.patch.object(BaseETL, 'from_db_query')
    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    def test__extract_and_load_data_partitioned(self, mock_get_query, mock_from_db_query, mock_obj_to_s3, asterisk):
        # arrange
        class_ = AsteriskTableEnum.CDR
        query_filename = '{}/asterisk/extract_{}_data.sql'.format(SOURCE_QUERIES_DIR, class_.value)
        query = "select 1 as foo from dummy"
        mock_get_query.return_value = query
        file_suffix = 'raw/asterisk/{}/dt={}/data.gz'.format(class_.value, asterisk.partition_date)
        mock_from_db_query.return_value = list(petl.fromdicts([{'foo': 1}], header=['foo']))
        s3_bucket = asterisk.s3_bucket

        # act
        asterisk._extract_and_load_data_partitioned(class_)

        # assert
        mock_get_query.assert_called_once_with(query_filename)
        mock_from_db_query.assert_called_once_with(query=query, db_enum=EnumDB.QuintoAndar_asterisk)
        assert mock_obj_to_s3.call_count == 1
        assert mock_obj_to_s3.call_args[1]['bucket'] == s3_bucket
        assert mock_obj_to_s3.call_args[1]['file_path'] == file_suffix

    @mock.patch.object(BaseETL, 'obj_to_s3')
    @mock.patch.object(BaseETL, 'from_db_query')
    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    def test__extract_and_load_data_full(self, mock_get_query, mock_from_db_query, mock_obj_to_s3, asterisk):
        # arrange
        class_ = AsteriskTableEnum.CDR
        query_filename = '{}/asterisk/extract_{}_data.sql'.format(SOURCE_QUERIES_DIR, class_.value)
        query = "select 1 as foo from dummy"
        mock_get_query.return_value = query
        file_suffix = 'raw/asterisk/{}/data.gz'.format(class_.value)
        mock_from_db_query.return_value = list(petl.fromdicts([{'foo': 1}], header=['foo']))
        s3_bucket = asterisk.s3_bucket

        # act
        asterisk._extract_and_load_data_full(class_)

        # assert
        mock_get_query.assert_called_once_with(query_filename)
        mock_from_db_query.assert_called_once_with(query=query, db_enum=EnumDB.QuintoAndar_asterisk)
        assert mock_obj_to_s3.call_count == 1
        assert mock_obj_to_s3.call_args[1]['bucket'] == s3_bucket
        assert mock_obj_to_s3.call_args[1]['file_path'] == file_suffix

    @mock.patch.object(AthenaClient, 'upsert_single_partition')
    def test__upsert_partition(self, mock_upsert_partition, asterisk):
        # arrange
        bucket_type = mock.ANY
        class_ = AsteriskTableEnum.CDR
        s3_bucket = asterisk.s3_bucket
        folder_path = '{}/{}/asterisk/{}'.format(s3_bucket, bucket_type, class_.value)
        partition_date = asterisk.partition_date
        database = 'datalake_{}'.format(bucket_type)
        table = 'asterisk_{}'.format(class_.value)
        partition_name = 'dt'

        # act
        asterisk._upsert_partition(bucket_type, class_)

        # assert
        mock_upsert_partition.assert_called_once_with(
            bucket_folder_path=folder_path,
            database=database,
            table=table,
            partition_name=partition_name,
            partition_value=partition_date
        )

    def test__upsert_partition_invalid_bucket_type(self, asterisk):
        # arrange
        bucket_type = 'dummy'
        class_ = AsteriskTableEnum.CDR

        # act & assert
        with pytest.raises(ValueError):
            asterisk._upsert_partition(bucket_type, class_)

    @mock.patch.object(AthenaClient, 'create_parquet_from_query')
    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    def test__move_to_clean_partitioned(self, mock_get_query, mock_create_parquet, asterisk):
        # arrange
        class_ = AsteriskTableEnum.CDR
        partition_date = asterisk.partition_date
        path = 'clean/asterisk/{}/dt={}/data.parq'.format(class_.value, partition_date)
        r_cols = OrderedDict([
            ('id', str)])
        c_cols = deepcopy(r_cols)
        query_filename = '{}/asterisk/create_{}_table.sql'.format(DATALAKE_QUERIES_DIR, class_.value)
        query = "select 1 as foo from dummy"
        mock_get_query.return_value = query

        # act
        asterisk._move_to_clean_partitioned(class_, r_cols, c_cols)

        # assert
        mock_get_query.assert_called_once_with(query_filename)
        mock_create_parquet.assert_called_once_with(
            key=path,
            query=query,
            raw_columns=r_cols,
            clean_columns=c_cols)

    @mock.patch.object(AthenaClient, 'create_parquet_from_query')
    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    def test__move_to_clean_full(self, mock_get_query, mock_create_parquet, asterisk):
        # arrange
        class_ = AsteriskTableEnum.CDR
        path = 'clean/asterisk/{}/data.parq'.format(class_.value)
        r_cols = OrderedDict([
            ('id', str)])
        c_cols = deepcopy(r_cols)
        query_filename = '{}/asterisk/create_{}_table.sql'.format(DATALAKE_QUERIES_DIR, class_.value)
        query = "select 1 as foo from dummy"
        mock_get_query.return_value = query

        # act
        asterisk._move_to_clean_full(class_, r_cols, c_cols)

        # assert
        mock_get_query.assert_called_once_with(query_filename)
        mock_create_parquet.assert_called_once_with(
            key=path,
            query=query,
            raw_columns=r_cols,
            clean_columns=c_cols)
