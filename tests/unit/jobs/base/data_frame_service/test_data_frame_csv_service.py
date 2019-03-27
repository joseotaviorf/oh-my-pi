import pandas as pd
import pytest


class TestDataFrameCSVService(object):

    def test_unicode_to_df(self, data_frame_csv_service):
        # arrange
        csv_content = u'col0,col1,col2\nrow0,row1,row2'
        df_result = pd.DataFrame({
            'col0': ['row0'],
            'col1': ['row1'],
            'col2': ['row2'],
        })

        # act
        result = data_frame_csv_service.unicode_to_df(csv_content=csv_content)

        # assert
        assert result.equals(df_result)

    @pytest.mark.parametrize('csv_content', ['str', 10, 10.])
    def test_unicode_to_df_with_invalid_csv_content_type(self, data_frame_csv_service, csv_content):
        # act & assert
        with pytest.raises(TypeError):
            data_frame_csv_service.unicode_to_df(csv_content=csv_content)
