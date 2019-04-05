class TestDataFrameService(object):

    def test_unset_df(self, data_frame_service):
        # act
        data_frame_service.unset_df()

        # assert
        assert data_frame_service.df is None
