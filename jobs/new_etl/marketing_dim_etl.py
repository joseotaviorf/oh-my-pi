from datetime import date
from dim_etl import DimensionETL
from jobs.base.base_etl import BaseETL, EnumDb
from marketing_costs.google_campaigns import GoogleCampaigns
from marketing_costs.fb_campaigns import FacebookCampaigns
from marketing_costs.criteo_campaigns import CriteoCampaigns
from qa_python_utils.default_logger import logger, _logger


class MarketingDimensionETL(DimensionETL):

    def __init__(self, bucket, mkt_configs):
        self.bucket = bucket
        self.facebook = FacebookCampaigns(mkt_configs['facebook'])
        self.google = GoogleCampaigns(mkt_configs['google'])
        self.criteo = CriteoCampaigns(mkt_configs['criteo'])

    def load_marketing_costs(self, dim_name):
        table_name = '{}_ads_campaigns'.format(dim_name)
        table = None
        if dim_name == 'google':
            table = self.google.extract_marketing_campaigns(date(2016, 1, 1))
        elif dim_name == 'facebook':
            table = self.facebook.extract_marketing_campaigns(date(2016, 11, 1))
        elif dim_name == 'criteo':
            table = self.criteo.extract_marketing_campaigns(date(2017, 1, 1))

        if table is not None:
            BaseETL.bulk_insert(
                table=table,
                table_name=table_name,
                db_enum=EnumDb.BI_ODS,
                encoding='UTF8',
                append=False,
                commit=True,
                bucket_name='{}/raw/ods/{}'.format(self.bucket, table_name)
            )
            BaseETL.copy_file_between_s3_buckets(
                bucket_source=self.bucket,
                bucket_destination=self.bucket,
                full_filename_source='raw/ods/{0}/{0}.csv'.format(table_name),
                full_filename_dest='clean/ods/{0}/{0}.csv'.format(table_name)
            )
        else:
            _logger.error("Failure to load marketing costs mc={} dt={}".format(dim_name, table_name.utcnow()))