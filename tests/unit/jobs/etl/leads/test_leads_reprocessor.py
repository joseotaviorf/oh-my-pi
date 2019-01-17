import time

import mock
import pandas as pd
import pytest
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.etl.leads.leads_reprocessor import LeadsReprocessor


class TestLeadsReprocessor(object):

    def test__check_required_params_with_missing_required_column(self, lead_reprocessor):
        # arrange
        config_dict = [{"id"}]
        required_columns = ['id', 'query']

        # act & assert
        with pytest.raises(ValueError):
            lead_reprocessor._check_required_params(config_dict=config_dict, required_columns=required_columns)

    def test__check_config_json_with_config_json_null(self, lead_reprocessor):
        # arrange
        config_json = None

        # act & assert
        with pytest.raises(ValueError):
            lead_reprocessor._check_config_json(config_json=config_json)

    @mock.patch.object(LeadsReprocessor, '_get_lead_ids_from_query', return_value=pd.DataFrame([{'id': 1}]))
    @mock.patch.object(LeadsReprocessor, '_treat_leads', return_value="""[{'id':1}]""")
    def test_get_leads(self, mock__treat_leads, mock__get_lead_ids_from_query, lead_reprocessor):
        # act
        result = lead_reprocessor.get_leads()

        # assert
        assert mock__treat_leads.call_count == 1
        assert mock__get_lead_ids_from_query.call_count == 1

    @mock.patch.object(BaseETL, 'publish_messages')
    @mock.patch.object(time, 'sleep')
    def test_send_leads(self, mock_sleep, mock_publish_messages, lead_reprocessor):
        # arrange
        json_list = """[{"id":1}, {"id":2}, {"id":3}]"""
        queue = 'queue'
        lead_reprocessor.batchSize = 1
        lead_reprocessor.sleep = 2

        # act
        lead_reprocessor.send_leads(json_list=json_list, queue=queue)

        # assert
        assert mock_publish_messages.call_count == 3
        assert mock_sleep.call_count == 3
        assert mock_sleep.call_args[0][0] == 2

    def test__treat_leads_without_id(self, lead_reprocessor):
        # arrange
        df_leads = pd.DataFrame(data=['select 1 from dummy'], columns=['query'])

        # act & assert
        with pytest.raises(ValueError):
            lead_reprocessor._treat_leads(df_leads=df_leads)

    @pytest.mark.parametrize('input, expected',
                             [(pd.DataFrame(data=[[1, 'test', '']], columns=['id', 'infosExtras', 'origem']),
                               '[{"infosExtras":"infosExtras test; id_origin_lead=1","origem":"Reprocessado"}]'),
                              (pd.DataFrame(data=[[1, '']], columns=['id', 'origem']),
                               '[{"origem":"Reprocessado","infosExtras":"infosExtras; id_origin_lead=1"}]')])
    def test__treat_leads_with_id(self, lead_reprocessor, input, expected):
        # arrange
        lead_reprocessor.infosExtras = 'infosExtras'
        expected_result = expected

        # act
        result = lead_reprocessor._treat_leads(df_leads=input)

        # assert
        assert result == expected_result

    @mock.patch.object(BaseETL, 'get_query_from_file_name',
                       return_value='select {columns} from dummy where id in ({where_clause})')
    @mock.patch.object(BaseETL, 'from_db_query', return_value=[('id', 'id2'), (1, 2)])
    def test__get_lead_ids_from_query(self, mock_from_db_query, mock_get_query_from_file_name, lead_reprocessor):
        # arrange
        lead_reprocessor.defaultColumns = {"id": "unsigned", "id2": "unsigned"}
        lead_reprocessor.query = 'select 1 from dummy'
        formatted_query = 'select cast(id2 as unsigned) as id2, cast(id as unsigned) as id from dummy where id in (select 1 from dummy)'
        expected_result = pd.DataFrame(data=[[1, 2]], columns=['id', 'id2'])

        # act
        result = lead_reprocessor._get_lead_ids_from_query()

        # assert
        assert mock_get_query_from_file_name.call_count == 1
        assert mock_from_db_query.call_count == 1
        assert mock_from_db_query.call_args[1].get('query') == formatted_query
        assert expected_result.equals(result)

    def test__split_into_chunks(self, lead_reprocessor):
        # arrange
        list_ = [1, 2, 3, 4, 5]
        chunk_size = 2
        expected_result = [[1, 2], [3, 4], [5]]

        # act
        # converting to list since the return from method is a generator via 'yield' command
        result = list(lead_reprocessor._split_into_chunks(list=list_, chunk_size=chunk_size))

        # assert
        assert result == expected_result

    def test__df_to_json(self, lead_reprocessor):
        # arrange
        df = pd.DataFrame(data=[1], columns=['id'])
        expected_result = '[{"id":1}]'

        # act
        result = lead_reprocessor._df_to_json(df=df)

        # assert
        # asserting string since pd.to_json returns a json string
        assert result == expected_result
