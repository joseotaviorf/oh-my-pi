from jobs.new_etl import DW_DIR
from jobs.new_etl.growth.incurred import Growth
from qa_python_utils.default_logger import logger


class GrowthPrediction(Growth):
    DEMAND_FUNNEL = 'demand'
    SUPPLY_FUNNEL = 'supply'
    PREDICTION_QUERIES_DIR = '{}/{}'.format(DW_DIR, 'growth/prod/queries/predictions')

    @staticmethod
    @logger
    def get_visits_booked_placeholders():
        return {
            'daily': 'booking_created',
            'weekly': 'booking_created_weekly_count',
            'monthly': 'booking_created_monthly_count',
            'yearly': 'booking_created_yearly_count'
        }

    @logger
    def create_table(self, funnel, measure, _filter, period, placeholders):
        prefix_file = GrowthPrediction.__get_query_from_file_name(
            '{}/prefix_{}.sql'.format(GrowthPrediction.PREDICTION_QUERIES_DIR, _filter))
        prefix_file_formatted = prefix_file.format(
            funnel=funnel,
            daily_count=placeholders['daily'],
            weekly_count=placeholders['weekly'],
            monthly_count=placeholders['monthly'],
            yearly_count=placeholders['yearly']
        )
        suffix_file = GrowthPrediction.__get_query_from_file_name('{}/suffix_{}.sql'.format(Growth.QUERIES_DIR, period))

        self.execute_command(
            'create table {}.prediction_{}_{}_{} as\n{}'.format(Growth.SCHEMA, measure, _filter, period,
                                                                prefix_file_formatted + suffix_file))
