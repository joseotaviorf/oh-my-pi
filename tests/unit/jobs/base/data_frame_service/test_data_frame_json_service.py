from io import BytesIO

import pandas as pd


class TestDataFrameJsonService(object):

    def test_to_json(self, data_frame_json_service):
        # arrange
        df = pd.DataFrame({
            'col0': ['row0'],
            'col1': ['row1'],
            'col2': ['row2'],
        })
        data_frame_json_service.df = df

        # act
        result = data_frame_json_service.to_json_bytes()

        # assert
        assert isinstance(result, BytesIO)
