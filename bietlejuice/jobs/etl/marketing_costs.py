import os
import sys
from datetime import date
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDb
from marketing_costs.google_campaigns import GoogleCampaigns
from marketing_costs.fb_campaigns import FacebookCampaigns
from marketing_costs.criteo_campaigns import CriteoCampaigns

if __name__ == '__main__':
    args = sys.argv
    bucket_datalake = os.environ['bi-datalake-s3-bucket']
    # TODO: Change from full extraction to incremental (see need for windowed incremental due to late campaign updates)
    if len(args) > 1:
        if args[1] == 'fb':
            fc = FacebookCampaigns()
            facebook_table = fc.extract_facebook_marketing_campaigns(date(2016, 11, 1))
            process_name = 'facebook_ads_campaigns'

            BaseETL.bulk_insert(
                table=facebook_table,
                table_name=process_name,
                db_enum=EnumDb.BI_ODS,
                encoding='UTF8',
                append=False,
                commit=True,
                bucket_name='{}/raw/ods/{}'.format(bucket_datalake, process_name)
            )
            BaseETL.copy_file_between_s3_buckets(
                bucket_source=bucket_datalake,
                bucket_destination=bucket_datalake,
                full_filename_source='raw/ods/{0}/{0}.csv'.format(process_name),
                full_filename_dest='clean/ods/{0}/{0}.csv'.format(process_name)
            )

        if args[1] == 'google':
            config_key = os.environ['ADWORDS_KEY']
            gc = GoogleCampaigns(config_key)
            ga_table = gc.extract_google_marketing_campaigns(date(2016, 1, 1))
            process_name = 'google_ads_campaigns'

            BaseETL.bulk_insert(
                table=ga_table,
                table_name=process_name,
                db_enum=EnumDb.BI_ODS,
                encoding='UTF8',
                append=False,
                commit=True,
                bucket_name='{}/raw/ods/{}'.format(bucket_datalake, process_name)
            )
            BaseETL.copy_file_between_s3_buckets(
                bucket_source=bucket_datalake,
                bucket_destination=bucket_datalake,
                full_filename_source='raw/ods/{0}/{0}.csv'.format(process_name),
                full_filename_dest='clean/ods/{0}/{0}.csv'.format(process_name)
            )

        if args[1] == 'criteo':
            criteo_config = os.environ['criteo']
            cc = CriteoCampaigns()
            criteo_table = cc.extract_criteo_marketing_campaigns(date(2017, 1, 1))
            process_name = 'criteo_ads_campaigns'

            BaseETL.bulk_insert(
                table=criteo_table,
                table_name=process_name,
                db_enum=EnumDb.BI_ODS,
                encoding='UTF8',
                append=False,
                commit=True,
                bucket_name='{}/raw/ods/{}'.format(bucket_datalake, process_name)
            )
            BaseETL.copy_file_between_s3_buckets(
                bucket_source=bucket_datalake,
                bucket_destination=bucket_datalake,
                full_filename_source='raw/ods/{0}/{0}.csv'.format(process_name),
                full_filename_dest='clean/ods/{0}/{0}.csv'.format(process_name)
            )
