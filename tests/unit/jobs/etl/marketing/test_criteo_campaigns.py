import mock

from bietlejuice.jobs.etl.marketing.criteo_campaigns import CriteoCampaigns


class TestCriteoCampaigns(object):

    @mock.patch.object(CriteoCampaigns, '_save_to_s3')
    def test_move_criteo_campaigns_to_raw(self, mock__save_to_s3, criteo_campaigns):
        # arrange
        client_id = 'client_id'
        client_secret = 'client_secret'

        # act
        criteo_campaigns.move_criteo_campaigns_to_raw()

        # assert
        assert mock__save_to_s3.call_count == 1
        assert mock__save_to_s3.call_args[0] == (client_id, client_secret)
