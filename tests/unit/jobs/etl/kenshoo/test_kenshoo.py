import pytest
from mock import Mock

from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.etl.kenshoo import Kenshoo


class TestKenshoo(object):

    @pytest.mark.parametrize('query_filename', [None, '', 'query'])
    def test_execute_query_from_file_with_invalid_query_filename(self, kenshoo, query_filename):
        # act & assert
        with pytest.raises(RuntimeError):
            kenshoo.execute_query_from_file(query_filename)

    def test_execute_query_from_file(self, kenshoo):
        # arrange
        query_filename = 'query_filename.sql'
        athena_query_filename = {
            'filename': '{}/{}/{}'.format(DATALAKE_QUERIES_DIR, Kenshoo.PREFIX_QUERIES_PATH, query_filename)
        }
        kenshoo.athena_client = Mock()

        # act
        kenshoo.execute_query_from_file(query_filename)

        # assert
        assert kenshoo.athena_client.execute_file_query_and_return_dataframe.call_args[1] == athena_query_filename
