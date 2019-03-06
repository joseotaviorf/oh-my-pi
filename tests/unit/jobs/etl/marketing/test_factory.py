import pytest
from datetime import datetime

from bietlejuice.jobs.etl.marketing import FacebookAds, GoogleAds
from bietlejuice.jobs.etl.marketing.marketing_enum import MarketingEnum


class TestMarketingFactory(object):
    @pytest.mark.parametrize('class_, expected',
                             [(MarketingEnum.FACEBOOK_ADS, FacebookAds),
                              (MarketingEnum.GOOGLE_ADS, GoogleAds)])
    def test_factory(self, factory, class_, expected):
        # act
        result = factory.factory(class_, 's3_bucket', datetime(2018, 1, 1))

        # assert
        assert result.__class__ == expected

    def test_factory_with_exception(self, factory):
        # act
        with pytest.raises(TypeError):
            factory.factory(None, 's3_bucket', datetime(2018, 1, 1))
