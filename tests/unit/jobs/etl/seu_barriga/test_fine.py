import mock

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.etl.seu_barriga import SeuBarrigaFine


class TestSeuBarrigaFine(object):

    @mock.patch.object(SeuBarrigaFine, '_request_data')
    def test_request_data(self, mock__request_data, seu_barriga_fine):
        # arrange
        endpoint_suffix = 'endpoint_suffix'
        endpoint_param = '{}/{}/{}'.format(endpoint_suffix, seu_barriga_fine.year, seu_barriga_fine.month)

        # act
        seu_barriga_fine.request_data(endpoint_suffix)

        # assert
        assert mock__request_data.call_args[0][0] == endpoint_param

    @mock.patch.object(BaseETL, 'get_query_from_file_name', return_value='select 1, 2, 3, 4 from dummy')
    @mock.patch.object(SeuBarrigaFine, '_transform_data')
    def test_transform_data(self, mock__transform_data, mock_get_query_from_file_name, seu_barriga_fine):
        # arrange
        query = 'select 1, 2, 3, 4 from dummy'
        invoice_file_name = 'fine_raw_transform.sql'
        table_name_param = 'seu_barriga_invoice_fine'
        type_param = str

        # act
        seu_barriga_fine.transform_data()

        # assert
        assert invoice_file_name in mock_get_query_from_file_name.call_args[0][0]
        assert mock__transform_data.call_args[1].get('query') == query

        for _, type_ in mock__transform_data.call_args[1]['raw_columns'].items():
            assert type_ == type_param
        for _, type_ in mock__transform_data.call_args[1]['clean_columns'].items():
            assert type_ == type_param

        assert mock__transform_data.call_args[1]['clean_table_name'] == table_name_param
