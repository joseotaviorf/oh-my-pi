from datetime import datetime

import pytest
from bietlejuice.jobs.etl.marketing import LifullCampaigns
from bietlejuice.jobs.etl.marketing.marketing_enum import MarketingEnum


class TestMarketingFactory(object):
    @pytest.mark.parametrize('class_, expected',
                             [(MarketingEnum.LIFULL, LifullCampaigns)])
    def test_factory(self, factory, class_, expected):
        # arrange
        auth = {'consumer_key': 'consumer_key', 'consumer_secret': 'consumer_secret',
                'access_token': 'access_token',
                'access_token_secret': 'access_token_secret',
                'client_id': 'client_id', 'client_secret': 'client_secret',
                'user': 'user'}
        extra_configs = {}

        # act
        result = factory.factory(class_, 's3_bucket', datetime(2018, 1, 1), auth, 'acc',
                                 extra_configs)

        # assert
        assert result.__class__ == expected
        assert result.execution_date == datetime(2018, 1, 1)

    @pytest.mark.parametrize('_enum, expected_class,expected_date',
                             [(MarketingEnum.LIFULL, LifullCampaigns,
                               datetime(2017, 12, 31))
                              ])
    def test_factory_with_offset_day(self, factory, _enum, expected_class,
                                     expected_date):
        # arrange
        auth = {'consumer_key': 'consumer_key', 'consumer_secret': 'consumer_secret',
                'access_token': 'access_token',
                'access_token_secret': 'access_token_secret',
                'client_id': 'client_id', 'client_secret': 'client_secret',
                'user': 'user'}

        # act
        result = factory.factory(_enum, 's3_bucket', datetime(2018, 1, 1), auth, 'acc',
                                 {'days_offset': 1})

        # assert
        assert result.__class__ == expected_class
        assert result.execution_date == expected_date

    def test_factory_with_exception(self, factory):
        # arrange
        auth = {"client_id": "client_id", "client_secret": "client_secret",
                "user": "user"}

        # act
        with pytest.raises(TypeError):
            factory.factory(None, 's3_bucket', datetime(2018, 1, 1), auth)

    @pytest.mark.parametrize("date,offset_days,expected_date",
                             [(datetime(2019, 9, 23), 1, datetime(2019, 9, 22)),
                              (datetime(2018, 3, 1), 2, datetime(2018, 2, 27)),
                              (datetime(2016, 3, 1), 2, datetime(2016, 2, 28)),
                              (datetime(2020, 1, 1), 5, datetime(2019, 12, 27))])
    def test__apply_offset_on_date(self, date, offset_days, expected_date, factory):
        # act
        result = factory._apply_offset_on_date(date, offset_days)

        # assert
        assert result == expected_date
