import pytest
from datetime import datetime

from bietlejuice.jobs.etl.marketing import FacebookAds, GoogleAds, ClassifiedsCosts, CriteoCampaigns, RtbCampaigns
from bietlejuice.jobs.etl.marketing.marketing_enum import MarketingEnum


class TestMarketingFactory(object):
    @pytest.mark.parametrize('class_, expected',
                             [(MarketingEnum.FACEBOOK_ADS, FacebookAds),
                              (MarketingEnum.GOOGLE_ADS, GoogleAds),
                              (MarketingEnum.CLASSIFIEDS_COSTS, ClassifiedsCosts),
                              (MarketingEnum.CRITEO, CriteoCampaigns),
                              (MarketingEnum.RTB, RtbCampaigns)])
    def test_factory(self, factory, class_, expected):
        # arrange
        auth = {"client_id": "client_id", "client_secret": "client_secret", "user": "user"}

        # act
        result = factory.factory(class_, 's3_bucket', datetime(2018, 1, 1), auth)

        # assert
        assert result.__class__ == expected

    def test_factory_with_exception(self, factory):
        # arrange
        auth = {"client_id": "client_id", "client_secret": "client_secret", "user": "user"}

        # act
        with pytest.raises(TypeError):
            factory.factory(None, 's3_bucket', datetime(2018, 1, 1), auth)
