import mock
from bietlejuice.jobs.etl.growth import GrowthPrediction


class TestGrowthPrediction(object):
    PLACEHOLDERS_KEY = ['daily_count', 'weekly_count', 'monthly_count', 'yearly_count']
    PLACEHOLDERS_VALUE = ['', '_weekly_count', '_monthly_count', '_yearly_count']

    def test_get_visits_booked_placeholders(self, growth_prediction):
        # arrange
        placeholder = 'booking_created'

        # act
        result = growth_prediction.get_visits_booked_placeholders()

        # assert
        assert len(result) == 4
        for item in self.PLACEHOLDERS_KEY:
            assert item in result
        for item in self.PLACEHOLDERS_VALUE:
            assert '{}{}'.format(placeholder, item) in result.values()

    def test_get_visits_completed_placeholders(self, growth_prediction):
        # arrange
        placeholder = 'effective_visit'

        # act
        result = growth_prediction.get_visits_completed_placeholders()

        # assert
        assert len(result) == 4
        for item in self.PLACEHOLDERS_KEY:
            assert item in result
        for item in self.PLACEHOLDERS_VALUE:
            assert '{}{}'.format(placeholder, item) in result.values()

    def test_get_offers_submitted_placeholders(self, growth_prediction):
        # arrange
        placeholder = 'offer_first_sent'

        # act
        result = growth_prediction.get_offers_submitted_placeholders()

        # assert
        assert len(result) == 4
        for item in self.PLACEHOLDERS_KEY:
            assert item in result
        for item in self.PLACEHOLDERS_VALUE:
            assert '{}{}'.format(placeholder, item) in result.values()

    def test_get_offers_approved_placeholders(self, growth_prediction):
        # arrange
        placeholder = 'offer_approved'

        # act
        result = growth_prediction.get_offers_approved_placeholders()

        # assert
        assert len(result) == 4
        for item in self.PLACEHOLDERS_KEY:
            assert item in result
        for item in self.PLACEHOLDERS_VALUE:
            assert '{}{}'.format(placeholder, item) in result.values()

    def test_get_documentation_sent_placeholders(self, growth_prediction):
        # arrange
        placeholder = 'tenant_first_document_sent'

        # act
        result = growth_prediction.get_documentation_sent_placeholders()

        # assert
        assert len(result) == 4
        for item in self.PLACEHOLDERS_KEY:
            assert item in result
        for item in self.PLACEHOLDERS_VALUE:
            assert '{}{}'.format(placeholder, item) in result.values()

    def test_get_approved_by_insurer_placeholders(self, growth_prediction):
        # arrange
        placeholder = 'credit_analysis_approved'

        # act
        result = growth_prediction.get_approved_by_insurer_placeholders()

        # assert
        assert len(result) == 4
        for item in self.PLACEHOLDERS_KEY:
            assert item in result
        for item in self.PLACEHOLDERS_VALUE:
            assert '{}{}'.format(placeholder, item) in result.values()

    def test_get_tenants_placeholders(self, growth_prediction):
        # arrange
        placeholder = 'signature_notcancelled'

        # act
        result = growth_prediction.get_tenants_placeholders()

        # assert
        assert len(result) == 4
        for item in self.PLACEHOLDERS_KEY:
            assert item in result
        for item in self.PLACEHOLDERS_VALUE:
            assert '{}{}'.format(placeholder, item) in result.values()

    @mock.patch.object(GrowthPrediction, '_execute_file_query')
    def test_append_predictions_fact(self, mock__execute_file_query, growth_prediction):
        # arrange
        fact_name = 'fact_growth'

        # act
        growth_prediction.append_predictions_fact()

        # assert
        assert mock__execute_file_query.call_count == 1
        assert 'predictions_{}'.format(fact_name) in mock__execute_file_query.call_args[0][0]
