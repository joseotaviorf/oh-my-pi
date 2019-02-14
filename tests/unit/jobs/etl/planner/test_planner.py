from copy import deepcopy

import mock
import pandas as pd
import pytest
import requests
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.etl.planner import PlannerTableEnum


class TestPlanner(object):
    @mock.patch.object(AthenaClient, 'execute_file_query_and_return_dataframe',
                       return_value=pd.DataFrame(data={'id': [1, 2], 'col2': ['foo', 'bar']}))
    def test__get_class_ids(self, mock_execute_file_query_and_return_dataframe, planner):
        # arrange
        entity = PlannerTableEnum.AGENT
        query_filename = '{}/planner/{}_ids.sql'.format(DATALAKE_QUERIES_DIR, entity.value)
        expected = [1, 2]

        # act
        result = planner._get_class_ids(entity)

        # assert
        assert mock_execute_file_query_and_return_dataframe.call_count == 1
        assert mock_execute_file_query_and_return_dataframe.call_args[1].get('filename') == query_filename
        assert result == expected

    @mock.patch.object(AthenaClient, 'execute_file_query_and_return_dataframe',
                       return_value=pd.DataFrame(data={'col1': [1, 2], 'col2': ['foo', 'bar']}))
    def test__get_class_ids_without_column_id(self, _, planner):
        # arrange
        entity = PlannerTableEnum.AGENT

        # act & assert
        with pytest.raises(RuntimeError):
            planner._get_class_ids(entity)

    @mock.patch.object(requests, 'get')
    def test__extract_data(self, mock_get, planner):
        # arrange
        endpoint = 'dummy'
        mock_get.return_value.ok = True
        expected = {'bar': 'bar', 'foo': 'foo'}
        mock_get.return_value.json.return_value = expected

        # act
        result = planner._extract_data(endpoint)

        # assert
        assert mock_get.call_count == 1
        assert result == expected

    @mock.patch.object(requests, 'get')
    def test__extract_data_with_error_response(self, mock_get, planner):
        # arrange
        endpoint = 'dummy'
        mock_get.return_value.ok = False

        # act & assert
        with pytest.raises(RuntimeError):
            planner._extract_data(endpoint)

    @mock.patch.object(BaseETL, 'obj_to_s3')
    def test__save_into_s3_raw(self, mock_obj_to_s3, planner):
        # arrange
        entity = PlannerTableEnum.AGENT
        id_class = 1
        file_suffix = 'raw/planner/dt={}/{}={}/data.gz'.format(planner.execution_date, entity.value, id_class)
        _json = [{'foo': 'foo', 'bar': 'bar'}]

        # act
        planner._save_into_s3_raw(_json, entity, id_class)

        # assert
        assert mock_obj_to_s3.call_count == 1
        assert mock_obj_to_s3.call_args[1].get('file_path') == file_suffix

    @mock.patch.object(BaseETL, 'obj_to_s3')
    def test__save_into_s3_raw_none(self, _, planner):
        # arrange
        entity = PlannerTableEnum.AGENT
        id_class = 1
        _json = None

        # act
        with pytest.raises(ValueError):
            planner._save_into_s3_raw(_json, entity, id_class)

    @mock.patch.object(AthenaClient, 'create_parquet_from_query')
    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    def test_def_move_to_clean(self, mock_get_query_from_file_name, mock_create_parquet_from_query, planner):
        # arrange
        id_class = 1
        entity = PlannerTableEnum.AGENT
        r_cols = {'id': str}
        c_cols = deepcopy(r_cols)
        query_filename = '{}/planner/{}_raw_transform.sql'.format(DATALAKE_QUERIES_DIR, entity.value)
        query = 'select 1 from dummy'
        mock_get_query_from_file_name.return_value = query
        key = 'clean/planner/dt={}/{}={}/data.parq'.format(planner.execution_date, entity.value, id_class)

        # act
        planner._move_to_clean(entity, id_class, r_cols, c_cols)

        # assert
        mock_get_query_from_file_name.assert_called_once_with(query_filename)
        mock_create_parquet_from_query.called_once_with(key=key, query=query, raw_columns=r_cols, clean_columns=c_cols)

    @mock.patch.object(AthenaClient, 'execute_file_query_and_wait_for_results')
    def test__upsert_single_raw_partition(self, mock_execute_file_query_and_wait_for_results,
                                          planner):
        # arrange
        id_class = 1
        entity = PlannerTableEnum.AGENT
        filename = '{}/planner/upsert_single_partition.sql'.format(DATALAKE_QUERIES_DIR)
        schema = 'datalake_raw'

        # act
        planner._upsert_single_raw_partition(entity, id_class)

        # assert
        assert mock_execute_file_query_and_wait_for_results.call_count == 1
        assert mock_execute_file_query_and_wait_for_results.call_args[1].get('filename') == filename
        assert mock_execute_file_query_and_wait_for_results.call_args[1].get('query_params') == {
            'schema': schema,
            'enum_value': entity.value,
            'dt_partition': planner.execution_date,
            'id_class': id_class,
            's3_bucket': planner.s3_bucket,
            'bucket_type': 'raw'}

    @mock.patch.object(AthenaClient, 'execute_file_query_and_wait_for_results')
    def test__upsert_single_clean_partition(self, mock_execute_file_query_and_wait_for_results, planner):
        # arrange
        id_class = 1
        entity = PlannerTableEnum.AGENT
        filename = '{}/planner/upsert_single_partition.sql'.format(DATALAKE_QUERIES_DIR)
        schema = 'datalake_clean'

        # act
        planner._upsert_single_clean_partition(entity, id_class)

        # assert
        assert mock_execute_file_query_and_wait_for_results.call_count == 1
        assert mock_execute_file_query_and_wait_for_results.call_args[1].get('filename') == filename
        assert mock_execute_file_query_and_wait_for_results.call_args[1].get('query_params') == {
            'schema': schema,
            'enum_value': entity.value,
            'dt_partition': planner.execution_date,
            'id_class': id_class,
            's3_bucket': planner.s3_bucket,
            'bucket_type': 'clean'}
