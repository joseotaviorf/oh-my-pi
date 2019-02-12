from collections import namedtuple

import mock
import numpy as np
import pandas as pd
import pytest
from bietlejuice.jobs.etl.autodialer import AutodialerETL, AutodialerEnum


class TestLeadsReprocessor(object):

    def test_wrong_connection_parameter(self, autodialer_etl):
        # arrange & act & assert
        with pytest.raises(Exception):
            class_ = AutodialerETL(mongo_client_uri='', bucket_name='5a-datalake', document_type_enum='task_references')

    @mock.patch.object(AutodialerETL, 'get_mongo_data', return_value=pd.DataFrame([np.array([1, 2, 3])]))
    @mock.patch.object(AutodialerETL, '_save_to_s3')
    def test_move_data_to_raw(self, mock__save_to_s3, mock_get_mongo_data, autodialer_etl):
        # act
        autodialer_etl.move_data_to_raw()

        # assert
        assert mock_get_mongo_data.call_count == 1
        assert mock__save_to_s3.call_count == 1
        assert mock__save_to_s3.call_args[1].get('json_list').equals(mock_get_mongo_data.return_value)

    @pytest.mark.parametrize('enum, db_key, expected',
                             [(AutodialerEnum.TASK_REFERENCES, 'taskReferences', 'taskReferences'),
                              (AutodialerEnum.TASK_REFERENCE_INBOUND_EVENTS, 'taskReferenceInboundEventHistories',
                               'taskReferenceInboundEventHistories'),
                              (AutodialerEnum.TASK_REFERENCE_OUTBOUND_EVENTS, 'taskReferenceOutboundHistory',
                               'taskReferenceOutboundHistory')
                              ])
    def test__mongo_connect_with_matching_enum(self, enum, db_key, expected, autodialer_etl):
        # arrange
        autodialer_etl.document_type_enum = enum

        # mocks a return to self.db object
        Db = namedtuple(db_key, [expected])
        db = Db(expected)
        autodialer_etl.db = db

        # act
        result = autodialer_etl._mongo_connect()

        # assert
        assert result == expected

    def test__mongo_connect_with_not_matching_enum(self, autodialer_etl):
        # arrange
        autodialer_etl.document_type_enum = ''

        # act & assert
        with pytest.raises(ValueError):
            result = autodialer_etl._mongo_connect()
