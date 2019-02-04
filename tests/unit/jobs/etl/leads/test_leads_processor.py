import decimal

import mock
import numpy as np
import pandas as pd
import petl
import pytest
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.etl.leads import LeadsProcessor
from bietlejuice.jobs.etl.leads.leads_processor import decimal_default
from shapely.geometry.polygon import Polygon


class TestLeadsProcessor(object):
    def test_get_unit_divisor_none(self, leads_processor):
        # arrange
        unit = None
        expected_result = None

        # act
        result = leads_processor.get_unit_divisor(unit=unit)

        # assert
        assert result is expected_result

    def test_get_unit_divisor_not_none(self, leads_processor):
        # arrange
        unit = 'week'
        expected_result = 7.0

        # act
        result = leads_processor.get_unit_divisor(unit=unit)

        # assert
        assert result == expected_result

    def test_get_polygons_not_none(self, leads_processor):
        # arrange
        poly = mock.ANY
        leads_processor._poly = poly
        expected_result = poly

        # act
        result = leads_processor.get_polygons()

        # assert
        assert result == expected_result

    @mock.patch.object(BaseETL, 'get_query_from_file_name', return_value='select 1 as col from dummy')
    @mock.patch.object(BaseETL, 'from_db_query',
                       return_value=petl.fromdicts([{"polygon": "Polygon((0 0,0 3,3 0,0 0),(1 1,1 2,2 1,1 1))"}]))
    def test_get_polygons_none(self, mock_from_db_query, mock_get_query_from_file_name, leads_processor):
        # arrange
        leads_processor._poly = None
        expected_result = pd.DataFrame(data=["POLYGON ((0 0, 0 3, 3 0, 0 0), (1 1, 1 2, 2 1, 1 1))"],
                                       columns=['polygon'])
        expected_data_type = 'Polygon'

        # act
        result = leads_processor.get_polygons()

        # assert
        assert mock_from_db_query.call_count == 1
        assert mock_get_query_from_file_name.call_count == 1
        assert mock_from_db_query.call_args[1].get('query') == mock_get_query_from_file_name.return_value
        assert len(result) == len(expected_result)
        assert str(result.polygon[0]) == expected_result.polygon[0]
        assert result.polygon[0].type == expected_data_type

    @pytest.mark.parametrize('lat, lng, expected', [('a', 'b', -1)])
    def test_check_coverage(self, lat, lng, expected, leads_processor):
        # act
        result = leads_processor.check_coverage(lat, lng)

        # assert
        assert result == expected

    @pytest.mark.parametrize('lat, lng, expected', [(0.5, 5, -1), (0.5, 0.5, 10)])
    @mock.patch.object(LeadsProcessor, 'get_polygons',
                       return_value=pd.DataFrame(data={'polygon': Polygon([(0, 0), (0, 1), (1, 1), (1, 0)]),
                                                       'region_id': 10}, index=[0]))
    def test_check_coverage_poly_none(self, mock_get_polygons, lat, lng, expected, leads_processor):
        # act
        result = leads_processor.check_coverage(lat, lng)

        # assert
        assert mock_get_polygons.call_count == 1
        assert result == expected

    @mock.patch.object(BaseETL, 'get_query_from_file_name', return_value='select 1 as col from dummy')
    @mock.patch.object(BaseETL, 'from_db_query', return_value=list(petl.data([['col'], [1]])))
    def test_get_reprocessed(self, mock_from_db_query, mock_get_query_from_file_name, leads_processor):
        # arrange
        expected_result = petl.todataframe([[1]])

        # act
        result = leads_processor.get_reprocessed()

        # assert
        assert mock_from_db_query.call_count == 1
        assert mock_get_query_from_file_name.call_count == 1
        assert mock_from_db_query.call_args[1].get('query') == mock_get_query_from_file_name.return_value
        assert result.equals(expected_result)

    @mock.patch.object(BaseETL, 'get_query_from_file_name',
                       return_value='select * from dummy where status {status_in} in \'{status_rule}\' and '
                                    'reason {reason_in} in \'{reason_rule}\' and week_interval = {week_interval}')
    @mock.patch.object(BaseETL, 'from_db_query', return_value=list(petl.data([['col'], [1]])))
    def test_get_contacts(self, mock_from_db_query, mock_get_query_from_file_name, leads_processor):
        # arrange
        week_interval = 1
        status_in = None
        reason_in = None
        statuses = ['active', 'deleted']
        reasons = ['lorem', 'ipsum']
        expected_query = 'select * from dummy where status not in \'active\', \'deleted\' and ' \
                         'reason not in \'lorem\', \'ipsum\' and week_interval = 1'
        expected_result = petl.todataframe([[1]])

        # act
        result = leads_processor.get_contacts(week_interval, status_in, reason_in, statuses, reasons)

        # assert
        assert mock_from_db_query.call_count == 1
        assert mock_get_query_from_file_name.call_count == 1
        assert mock_from_db_query.call_args[1].get('query') == expected_query
        assert result.equals(expected_result)

    @mock.patch.object(BaseETL, 'from_db_query', return_value=list(petl.data([['col'], [1]])))
    @mock.patch.object(LeadsProcessor, '_build_time_interval_filter', return_value='dt between 1 and 2')
    def test_read_leads(self, mock__build_time_interval_filter, mock_from_db_query, leads_processor):
        # arrange
        origin = ['o1']
        status = ['s1']
        reason = ['r1']
        interval = 1
        unit = ''
        expected_result = petl.todataframe([[1]])
        expected_query = 'select * from Lead\nwhere origem in (\'o1\')\nand status in (\'s1\')\n' \
                         'and reason in (\'r1\')\nand dt between 1 and 2'

        # act
        result = leads_processor.read_leads(origin=origin, status=status, reason=reason, interval=interval, unit=unit)

        # assert
        assert mock_from_db_query.call_count == 1
        assert mock__build_time_interval_filter.call_count == 1
        assert mock_from_db_query.call_args[1].get('query') == expected_query
        assert result.equals(expected_result)

    def test__build_leads_list_with_no_key_matching(self, leads_processor):
        # arrange
        leads = pd.DataFrame(data=[1], columns=['id'])

        # act & assert
        with pytest.raises(KeyError):
            result = leads_processor._build_leads_list(leads)

    def test__build_leads_list_with_key_matching(self, leads_processor):
        # arrange
        leads = pd.DataFrame(
            data=[['lorem ipsum', np.nan, np.nan, np.nan, np.nan, np.nan, np.nan, np.nan, np.nan, np.nan, np.nan, np.nan,
                  np.nan, np.nan, np.nan, np.nan, np.nan, np.nan]],
            columns=['origem', 'tipo', 'cep', 'cidade', 'bairro', 'endereco', 'numero', 'complemento',
                     'lat', 'lng',
                     'valor', 'nomeAnunciante', 'telefoneAnunciante', 'telefoneAnuncianteDois',
                     'telefoneAnuncianteTres',
                     'email', 'infosExtras', 'referencia'])
        expected_result = '{\"referencia\": NaN, \"complemento\": NaN, \"tipo\": NaN, \"bairro\": NaN, ' \
                          '"cidade\": NaN, \"origem\": \"lorem ipsum\", \"numero\": NaN, \"telefoneAnunciante\": NaN,' \
                          ' "infosExtras\": NaN, \"telefoneAnuncianteDois\": NaN, \"nomeAnunciante\": NaN, ' \
                          '"valor\": NaN, \"cep\": NaN, \"lat\": NaN, \"endereco\": NaN, \"lng\": NaN, ' \
                          '"email\": NaN, \"telefoneAnuncianteTres\": NaN}'

        # act
        result = leads_processor._build_leads_list(leads)

        # assert
        assert result[0] == expected_result

    @mock.patch.object(BaseETL, 'publish_messages')
    @mock.patch.object(LeadsProcessor, '_build_leads_list', return_value='[{id:1}]')
    def test_send_leads(self, mock__build_leads_list, mock_publish_messages, leads_processor):
        # arrange
        leads = pd.DataFrame(data=[1], columns=['id'])

        # act
        leads_processor.send_leads(leads=leads)

        # assert
        assert mock__build_leads_list.call_count == 1
        assert leads.equals(mock__build_leads_list.call_args[0][0])
        assert mock_publish_messages.call_count == 1
        assert mock_publish_messages.call_args[1].get('messages') == mock__build_leads_list.return_value

    def test_decimal_default_not_none(self):
        # arrange
        str_decimal = decimal.Decimal(20.90)
        expected_result = float(20.9)

        # act
        result = decimal_default(str_decimal)

        # assert
        assert result == expected_result

    @pytest.mark.parametrize('str_decimal', ['20.90', None])
    def test_decimal_default_str(self, str_decimal):
        # act & assert
        with pytest.raises(TypeError):
            result = decimal_default(str_decimal)

    @pytest.mark.parametrize('categories, expected', [(None, None), ('Lorem Ipsum', None)])
    def test__build_categorical_filter_categories_none(self, leads_processor, categories, expected):
        # arrange
        column = None

        # act
        result = leads_processor._build_categorical_filter(column=column, categories=categories)

        # assert
        assert result is expected

    @pytest.mark.parametrize('column, categories, expected', [('0', ['0', '1'], """0 in ('0', '1')\n"""),
                                                              ('0', ['1', '2'], """0 in ('1', '2')\n""")])
    def test___build_categorical_filter_categories_list(self, leads_processor, column, categories, expected):
        # act
        result = leads_processor._build_categorical_filter(column=column, categories=categories)

        # assert
        assert result == expected

    @mock.patch.object(LeadsProcessor, 'get_unit_divisor', return_value=None)
    def test__build_time_interval_filter_u_none(self, mock_get_unit_divisor, leads_processor):
        # arrange
        column = None
        interval = None
        unit = None
        expected_result = None

        # act
        result = leads_processor._build_time_interval_filter(column=column, interval=interval, unit=unit)

        # assert
        assert mock_get_unit_divisor.call_count == 1
        assert mock_get_unit_divisor.call_args[0][0] == unit
        assert result is expected_result

    @pytest.mark.parametrize('interval, expected', [(None, None), ('1', None)])
    @mock.patch.object(LeadsProcessor, 'get_unit_divisor', return_value=1.0)
    def test__build_time_interval_filter_interval_none(self, mock_get_unit_divisor, interval, expected,
                                                       leads_processor):
        # arrange
        column = None
        unit = 'day'

        # act
        result = leads_processor._build_time_interval_filter(column=column, interval=interval, unit=unit)

        # assert
        assert mock_get_unit_divisor.call_count == 1
        assert mock_get_unit_divisor.call_args[0][0] == unit
        assert result is expected

    @mock.patch.object(LeadsProcessor, 'get_unit_divisor', return_value=1.0)
    def test__build_time_interval_filter_interval_not_none(self, mock_get_unit_divisor, leads_processor):
        # arrange
        interval = ['1', '2']
        column = None
        unit = 'day'
        expected_result = 'floor(datediff(utc_timestamp(), None)/1.00) between 1 and 2\n'

        # act
        result = leads_processor._build_time_interval_filter(column=column, interval=interval, unit=unit)

        # assert
        assert mock_get_unit_divisor.call_count == 1
        assert mock_get_unit_divisor.call_args[0][0] == unit
        assert result == expected_result

    @mock.patch.object(LeadsProcessor, 'get_unit_divisor', return_value=1.0)
    def test__build_time_interval_filter_interval_one_item_only(self, mock_get_unit_divisor, leads_processor):
        # arrange
        interval = ['1']
        column = None
        unit = 'day'

        # act & assert
        with pytest.raises(IndexError):
            result = leads_processor._build_time_interval_filter(column=column, interval=interval, unit=unit)
        assert mock_get_unit_divisor.call_count == 1
