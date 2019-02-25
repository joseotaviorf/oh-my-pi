from datetime import datetime

import mock
import requests
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.etl.seu_barriga import SeuBarrigaFine


class TestSeuBarrigaFine(object):

    @mock.patch.object(SeuBarrigaFine, '_request_data', return_value=requests.get(url='http://quintoandar.com.br'))
    def test_request_data(self, mock__request_data, seu_barriga_fine):
        # arrange
        endpoint_suffix = mock.ANY
        year = datetime.today().strftime('%Y')
        month = datetime.today().strftime('%m')
        endpoint_param = '{}/{}/{}'.format(endpoint_suffix, year, month)
        expected_result = requests.get(url='http://quintoandar.com.br').content

        # act
        result = seu_barriga_fine.request_data(endpoint_suffix)

        # assert
        assert mock__request_data.call_count == 1
        assert mock__request_data.call_args[0][0] == endpoint_param
        assert str(result) == str(expected_result)

    @mock.patch.object(BaseETL, 'get_query_from_file_name', return_value='select 1, 2, 3, 4 from dummy')
    @mock.patch.object(SeuBarrigaFine, '_transform_data')
    def test_transform_data(self, mock__transform_data, mock_get_query_from_file_name, seu_barriga_fine):
        # arrange
        query = 'select 1, 2, 3, 4 from dummy'
        invoice_file_name = 'fine_raw_transform.sql'
        r_cols = ['contract-external-id', 'fine', 'due-date', 'paid-date']
        c_cols = ['contract_id', 'fine', 'due_date', 'paid_date']
        table_name_param = 'seu_barriga_invoice_fine'

        # act
        seu_barriga_fine.transform_data()

        # assert
        assert mock_get_query_from_file_name.call_count == 1
        assert invoice_file_name in mock_get_query_from_file_name.call_args[0][0]
        assert mock__transform_data.call_count == 1
        assert mock__transform_data.call_args[1].get('query') == query
        for item in r_cols:
            assert item in mock__transform_data.call_args[1].get('raw_columns')
        for item in c_cols:
            assert item in mock__transform_data.call_args[1].get('clean_columns')
        assert mock__transform_data.call_args[1].get('clean_table_name') == table_name_param
