import mock
import pytest

from bietlejuice.jobs.dags.marketing.marketing_facebook_ads_subdag import \
    MarketingFacebookAdsSubDag
from bietlejuice.jobs.dags.marketing.marketing_google_ads_subdag import \
    MarketingGoogleAdsSubDag
from bietlejuice.jobs.dags.marketing.marketing_rtb_campaigns_subdag import \
    MarketingRtbCampaignsSubDag
from bietlejuice.jobs.dags.marketing.marketing_subdag_factory import \
    MarketingSubDagFactory
from bietlejuice.jobs.dags.marketing.marketing_twitter_campaigns_subdag import \
    MarketingTwitterCampaignsSubDag
from bietlejuice.jobs.etl.marketing.marketing_enum import MarketingEnum


class TestMarketingSubdagFactory(object):

    @pytest.mark.parametrize('class_, expected', [
        (MarketingEnum.GOOGLE_ADS, MarketingGoogleAdsSubDag),
        (MarketingEnum.FACEBOOK_ADS, MarketingFacebookAdsSubDag),
        (MarketingEnum.RTB, MarketingRtbCampaignsSubDag),
        (MarketingEnum.TWITTER, MarketingTwitterCampaignsSubDag)
    ])
    def test_factory(self, class_, expected):
        # act
        result = MarketingSubDagFactory.factory(class_, 'bucket', 'sub_dag_name',
                                                'dag_name', 'schedule_interval',
                                                'start_date', end_date=None,
                                                accounts=None, auth=None,
                                                extra_configs=None)

        # assert
        assert isinstance(result, expected)

    def test_factory_with_invalid_class(self):
        # arrange
        class_ = mock.ANY

        # assert
        with pytest.raises(RuntimeError):
            # act
            MarketingSubDagFactory.factory(class_, 'bucket', 'sub_dag_name',
                                           'dag_name', 'schedule_interval',
                                           'start_date', end_date=None,
                                           accounts=None, auth=None, extra_configs=None)

    def test_factory_with_none_table(self):
        # arrange
        class_ = None

        # assert
        with pytest.raises(RuntimeError):
            # act
            MarketingSubDagFactory.factory(class_, 'bucket', 'sub_dag_name',
                                           'dag_name', 'schedule_interval',
                                           'start_date', end_date=None,
                                           accounts=None, auth=None, extra_configs=None)
