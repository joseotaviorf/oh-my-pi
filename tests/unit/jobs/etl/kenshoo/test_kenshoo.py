import datetime
from os import listdir
from os.path import isfile, join

import mock
import pandas as pd
import petl
import pytest
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.etl.kenshoo import Kenshoo
from qa_python_utils.aws.athena import AthenaClient


class TestKenshoo(object):

    @pytest.mark.parametrize('query_filename, athena_client, file_name, query_params',
                             [[None, '', '', None], ['', '', '', None], ['query', '', '', None],
                              ['sql.sql', None, '', None]])
    def test_save_file_from_athena_query_execution_with_wrong_param(self, kenshoo, query_filename, athena_client,
                                                                    file_name, query_params):
        # act & assert
        with pytest.raises(RuntimeError):
            kenshoo.save_file_from_athena_query_execution(query_filename, athena_client, file_name,
                                                          query_params=query_params)

    @pytest.mark.parametrize('query_filename', [None, '', 'query'])
    def test_save_file_from_redshift_query_execution_with_wrong_param(self, kenshoo, query_filename):
        # act & assert
        with pytest.raises(RuntimeError):
            kenshoo.save_file_from_redshift_query_execution(query_filename)

    @mock.patch.object(Kenshoo, '_athena_execute_query_from_file', return_value=pd.DataFrame(data=[1], columns=['id']))
    @mock.patch.object(Kenshoo, '_save_single_file')
    def test_save_file_from_athena_query_execution(self, mock__save_single_file,
                                                   mock__athena_execute_query_from_file, kenshoo):
        # arrange
        query_filename = 'query.sql'
        athena_client = 'mock_athena_client'
        file_name = mock.ANY
        query_params = None

        # act
        kenshoo.save_file_from_athena_query_execution(query_filename=query_filename, athena_client=athena_client,
                                                      file_name=file_name)

        # assert
        mock__save_single_file.assert_called_once_with(df=mock__athena_execute_query_from_file.return_value,
                                                       file_name=file_name)
        mock__athena_execute_query_from_file.assert_called_once_with(query_filename=query_filename,
                                                                     athena_client=athena_client,
                                                                     query_params=query_params)

    @mock.patch.object(Kenshoo, '_redshift_execute_query_from_file',
                       return_value=pd.DataFrame(data=[1], columns=['id']))
    @mock.patch.object(Kenshoo, '_save_single_file')
    def test_save_file_from_redshift_query_execution_single_file(self, mock__save_single_file,
                                                                 mock__redshift_execute_query_from_file, kenshoo):
        # arrange
        query_filename = 'query.sql'
        query_params = mock.ANY
        split_by_column = None

        # act
        kenshoo.save_file_from_redshift_query_execution(query_filename=query_filename, query_params=query_params,
                                                        split_by_column=split_by_column)

        # assert
        mock__save_single_file.assert_called_once_with(df=mock__redshift_execute_query_from_file.return_value)
        mock__redshift_execute_query_from_file.assert_called_once_with(query_filename=query_filename,
                                                                       query_params=query_params)

    @mock.patch.object(Kenshoo, '_redshift_execute_query_from_file',
                       return_value=pd.DataFrame(data=[1], columns=['id']))
    @mock.patch.object(Kenshoo, '_save_multiple_files')
    def test_save_file_from_redshift_query_execution_multiple_file(self, mock__save_multiple_files,
                                                                   mock__redshift_execute_query_from_file, kenshoo):
        # arrange
        query_filename = 'query.sql'
        query_params = mock.ANY
        split_by_column = 'Lorem'

        # act
        kenshoo.save_file_from_redshift_query_execution(query_filename=query_filename, query_params=query_params,
                                                        split_by_column=split_by_column)

        # assert
        mock__save_multiple_files.assert_called_once_with(df=mock__redshift_execute_query_from_file.return_value,
                                                          query_filename=query_filename,
                                                          split_by_column=split_by_column)
        mock__redshift_execute_query_from_file.assert_called_once_with(query_filename=query_filename,
                                                                       query_params=query_params)

    @mock.patch.object(AthenaClient, 'execute_file_query_and_return_dataframe',
                       return_value=pd.DataFrame(data=[1], columns=['id']))
    def test__athena_execute_query_from_file(self, mock_execute_file_query_and_return_dataframe, kenshoo):
        # arrange
        full_path = mock.ANY
        query_filename = mock.ANY
        athena_client = AthenaClient('')
        expected_result = pd.DataFrame(data=[1], columns=['id'])
        query_params = None

        # act
        result = kenshoo._athena_execute_query_from_file(query_filename, athena_client, query_params)

        # assert
        assert result.equals(expected_result)
        mock_execute_file_query_and_return_dataframe.assert_called_once_with(filename=full_path,
                                                                             query_params=query_params)

    @mock.patch.object(BaseETL, 'from_db_query',
                       return_value=petl.fromdicts([{"id": 1}]))
    def test__redshift_execute_query_from_file(self, mock_from_db_query, kenshoo):
        # arrange
        query_filename = 'visits_accomplished.sql'
        query_params = None
        expected_result = pd.DataFrame(data=[1], columns=['id'])

        # act
        result = kenshoo._redshift_execute_query_from_file(query_filename, query_params)

        # assert
        assert result.equals(expected_result)
        assert mock_from_db_query.call_count == 1

    def test__save_single_file(self, kenshoo):
        # arrange
        path = '/tmp'
        kenshoo.execution_date = datetime.datetime(2000, 1, 1)
        file_name = 'test'
        full_path = '{}-{}{}.csv'.format('kenshoo', file_name, kenshoo.execution_date)
        df = pd.DataFrame(data=[1], columns=['id'])

        # act
        kenshoo._save_single_file(df=df, file_name=file_name)

        # assert
        files = [f for f in listdir(path) if isfile(join(path, f))]
        assert full_path in files

    def test__save_multiple_files(self, kenshoo):
        # arrange
        query_filename = 'test'
        path = '/tmp'

        kenshoo.execution_date = datetime.datetime(2000, 01, 01)
        df = pd.DataFrame(data=[['lorem'], ['ipsum']], columns=['id'])
        expected_result = ['kenshoo-test-lorem.csv', 'kenshoo-test-ipsum.csv']
        split_by_column = 'id'

        # act
        kenshoo._save_multiple_files(df=df, query_filename=query_filename, split_by_column=split_by_column)

        # assert
        files = [f for f in listdir(path) if isfile(join(path, f))]
        for item in expected_result:
            assert item in files
