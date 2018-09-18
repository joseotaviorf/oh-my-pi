from qa_python_utils.default_logger import logger, _logger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.new_etl import DW_QUERIES_DIR
from bietlejuice.jobs.new_etl.growth.incurred import Growth


class GrowthPrediction(Growth):
    DEMAND_FUNNEL = 'demand'
    SUPPLY_FUNNEL = 'supply'
    PREDICTION_QUERIES_DIR = '{}/growth/predictions'.format(DW_QUERIES_DIR)

    @staticmethod
    @logger
    def get_visits_booked_placeholders():
        return {
            'daily_count': 'booking_created',
            'weekly_count': 'booking_created_weekly_count',
            'monthly_count': 'booking_created_monthly_count',
            'yearly_count': 'booking_created_yearly_count'
        }

    @staticmethod
    @logger
    def get_visits_completed_placeholders():
        return {
            'daily_count': 'effective_visit',
            'weekly_count': 'effective_visit_weekly_count',
            'monthly_count': 'effective_visit_monthly_count',
            'yearly_count': 'effective_visit_yearly_count'
        }

    @staticmethod
    @logger
    def get_offers_submitted_placeholders():
        return {
            'daily_count': 'offer_first_sent',
            'weekly_count': 'offer_first_sent_weekly_count',
            'monthly_count': 'offer_first_sent_monthly_count',
            'yearly_count': 'offer_first_sent_yearly_count'
        }

    @staticmethod
    @logger
    def get_offers_approved_placeholders():
        return {
            'daily_count': 'offer_approved',
            'weekly_count': 'offer_approved_weekly_count',
            'monthly_count': 'offer_approved_monthly_count',
            'yearly_count': 'offer_approved_yearly_count'
        }

    @staticmethod
    @logger
    def get_documentation_sent_placeholders():
        return {
            'daily_count': 'tenant_first_document_sent',
            'weekly_count': 'tenant_first_document_sent_weekly_count',
            'monthly_count': 'tenant_first_document_sent_monthly_count',
            'yearly_count': 'tenant_first_document_sent_yearly_count'
        }

    @staticmethod
    @logger
    def get_approved_by_insurer_placeholders():
        return {
            'daily_count': 'credit_analysis_approved',
            'weekly_count': 'credit_analysis_approved_weekly_count',
            'monthly_count': 'credit_analysis_approved_monthly_count',
            'yearly_count': 'credit_analysis_approved_yearly_count'
        }

    @staticmethod
    @logger
    def get_tenants_placeholders():
        return {
            'daily_count': 'signature_notcancelled',
            'weekly_count': 'signature_notcancelled_weekly_count',
            'monthly_count': 'signature_notcancelled_monthly_count',
            'yearly_count': 'signature_notcancelled_yearly_count'
        }

    @staticmethod
    def create_prediction_table(funnel, measure, _filter, period, placeholders):
        _logger.info(
            'm=create_table, funnel={}, measure={}, _filter={}, period={}, placeholders={}'.format(funnel, measure,
                                                                                                   _filter, period,
                                                                                                   placeholders))
        prefix_file = BaseETL.get_query_from_file_name(
            '{}/prefix_{}.sql'.format(GrowthPrediction.PREDICTION_QUERIES_DIR, _filter))
        prefix_file_formatted = prefix_file.format(
            funnel=funnel,
            daily_count=placeholders['daily_count'],
            weekly_count=placeholders['weekly_count'],
            monthly_count=placeholders['monthly_count'],
            yearly_count=placeholders['yearly_count']
        )
        suffix_file = BaseETL.get_query_from_file_name(
            '{}/suffix_{}.sql'.format(GrowthPrediction.QUERIES_DIR, period))

        GrowthPrediction.execute_command(
            'create table {}.{}_{}_{} as\n{}'.format(GrowthPrediction.SCHEMA, measure, _filter, period,
                                                     prefix_file_formatted + suffix_file)
        )

    @staticmethod
    @logger
    def append_predictions_fact():
        GrowthPrediction._execute_file_query(
            '{}/public/predictions_{}.sql'.format(DW_QUERIES_DIR, GrowthPrediction.FACT_TABLE_NAME))
