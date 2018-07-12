# coding=utf-8

from datetime import datetime, timedelta

from qa_python_utils.default_logger import logger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.new_etl import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.new_etl.crawlers.crawler_entity import CrawlerEntity


class CrawlerCPFs(CrawlerEntity):
    def __init__(self, s3_bucket, google_maps_api_key):
        super(CrawlerCPFs, self).__init__(s3_bucket=s3_bucket, google_maps_api_key=google_maps_api_key)

    @logger
    def get_locations(self, ws, delta_days):
        last_date = datetime.strptime(self.get_last_crawling_date(ws), '%Y-%m-%d')

        if delta_days > 0:
            since = last_date - timedelta(days=delta_days)
        else:
            since = last_date

        q = BaseETL.get_query_from_file_name('{}/crawlers/get_recent_locations.sql'.format(DATALAKE_QUERIES_DIR))
        q = q.replace('__LAST_CRAWLER_RUN__', since.strftime('%Y-%m-%d'))

        return self.athena_client.execute_query_and_return_dataframe(q)
