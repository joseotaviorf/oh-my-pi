# coding=utf-8

import re
from datetime import datetime, timedelta

import pandas as pd
from qa_python_utils.default_logger import logger, _logger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.new_etl import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.new_etl.crawlers.crawler_entity import CrawlerEntity


class CrawlerCPFs(CrawlerEntity):

    def __init__(self, s3_bucket, google_maps_api_key):
        super(CrawlerCPFs, self).__init__(s3_bucket=s3_bucket, google_maps_api_key=google_maps_api_key)

    def parse_address(self, data):
        pattern = re.compile(r'-(.*)-n-(\d+)|-(.*)')
        data['street_name'] = data.street.apply(lambda x: self._search_pattern(x, pattern, 1))
        data['street_name'] = data.street_name.combine_first(
            data.street.apply(lambda x: self._search_pattern(x, pattern, 3)))
        data['street_name'] = data.street_name.apply(lambda x: x.replace('-', ' ') if x is not None else None)
        data['street_number'] = data.street.apply(lambda x: self._search_pattern(x, pattern, 2))

        return data

    @logger(exclude='data')
    def fill_in(self, data, limit, allow_enrichment=True):
        data = self.parse_address(data)

        to_fill = """street_name.isnull() or street_number.isnull()"""
        as_ref = """~street_name.isnull() and ~street_number.isnull()"""

        n_locations = len(data.query(as_ref).groupby(['street_name', 'street_number']).size())

        if allow_enrichment is False or n_locations >= limit:
            return data.query(as_ref)

        df_to_fill = data.query(to_fill)
        for i, row in df_to_fill.iterrows():
            try:
                df_as_ref = data.query(as_ref)
                actual_address = df_as_ref.loc[
                    (df_as_ref.lat == row.lat) & (df_as_ref.lng == row.lng), ['street_name', 'street_number']]

                if actual_address.empty:
                    street, number = self.reverse_geocode(row.lat, row.lng)
                    street = ' '.join(street.split(' ')[1:])
                    n_locations += 1
                else:
                    street = actual_address.iloc[0].street_name
                    number = actual_address.iloc[0].street_number

                data.loc[i, 'street_name'] = street.lower()
                data.loc[i, 'street_number'] = number
            except Exception:
                _logger.warn('m=fill_in, could not retrieve street and number.')

            if n_locations >= limit:
                break

        return data.query(as_ref)

    @logger
    def get_locations(self, ws, delta_days):
        last_date = datetime.strptime(self.get_last_crawling_date(ws), '%Y-%m-%d')
        since = last_date - timedelta(days=delta_days)

        q = BaseETL.get_query_from_file_name('{}/crawlers/get_locations.sql'.format(DATALAKE_QUERIES_DIR))
        q = q.format(ws=ws, started_on=last_date.strftime('%Y-%m-%d'), since=since.strftime('%Y-%m-%d'))

        return self.athena_client.execute_query_and_return_dataframe(q)

    @logger(exclude='locations')
    def check_locations_coverage(self, locations):
        # get to which region each lead belongs
        _logger.info('m=crawl_cpfs, checking coverage')
        locations['regions'] = locations.apply(lambda row: self.check_coverage(row.lat, row.lng), axis=1)
        # filter out units outside our coverage area
        return locations[
            (locations.regions > -1) & ((~locations.type.str.contains('casa')) |
                                        locations.regions.isin(self.house_allowed))]

    @logger(exclude='locations')
    def check_neighborhoods(self, locations, neighborhood):
        if neighborhood is None:
            return pd.DataFrame(columns=locations.columns)

        if not isinstance(neighborhood, list):
            neighborhood = [neighborhood]

        neighborhood = [self.sanitize_text(n) for n in neighborhood]
        return locations[locations.neighborhood.isin(neighborhood)]
