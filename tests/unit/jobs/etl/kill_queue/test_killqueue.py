from collections import OrderedDict
from copy import deepcopy

import mock
import petl
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR, SOURCE_QUERIES_DIR


class TestKillQueue(object):

    @mock.patch.object(BaseETL, 'obj_to_s3')
    @mock.patch.object(BaseETL, 'from_db_query', return_value=list(petl.fromdicts([{'foo': 1}], header=['foo'])))
    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    def test__extract_data_and_move_to_raw(self, mock_get_query_from_file_name, mock_from_db_query,
                                           mock_obj_to_s3, kill_queue):
        # arrange
        table = 'table'
        file_query = '{}/kill_queue/extract_{}_data.sql'.format(SOURCE_QUERIES_DIR, table)
        query = 'select 1 from dummy'
        mock_get_query_from_file_name.return_value = query
        db_enum = EnumDB.QuintoAndar_killqueue
        out_file_path = 'raw/kill_queue/{}/data.gz'.format(table)

        # act
        kill_queue._extract_data_and_move_to_raw(table)

        # assert
        assert mock_get_query_from_file_name.call_count == 1
        assert mock_get_query_from_file_name.call_args[0][0] == file_query
        assert mock_from_db_query.call_count == 1
        assert mock_from_db_query.call_args[1].get('query') == query
        assert mock_from_db_query.call_args[1].get('db_enum') == db_enum
        assert mock_obj_to_s3.call_count == 1
        assert mock_obj_to_s3.call_args[1].get('file_path') == out_file_path

    @mock.patch.object(AthenaClient, 'create_parquet_from_query')
    @mock.patch.object(BaseETL, 'get_query_from_file_name')
    def test__move_data_from_raw_to_clean(self, mock_get_query_from_filename, mock_create_parquet_from_query,
                                          kill_queue):
        # arrange
        table = 'table'
        r_cols = OrderedDict({'id': str})
        c_cols = deepcopy(r_cols)
        query_filename = '{}/kill_queue/{}.sql'.format(DATALAKE_QUERIES_DIR, table)
        query = 'select 1 from dummy'
        mock_get_query_from_filename.return_value = query
        out_file_path = 'clean/kill_queue/{}/data.parq'.format(table)

        # act
        kill_queue._move_data_from_raw_to_clean(table, r_cols, c_cols)

        # assert
        mock_get_query_from_filename.assert_called_once_with(query_filename)
        assert mock_create_parquet_from_query.call_count == 1
        assert mock_create_parquet_from_query.call_args[1] == {'key': out_file_path, 'query': query,
                                                               'raw_columns': r_cols, 'clean_columns': c_cols}
