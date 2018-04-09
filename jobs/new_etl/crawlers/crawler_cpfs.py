# coding=utf-8

import re
from datetime import datetime, timedelta

import pandas as pd
from jobs.base.base_etl import BaseETL
from jobs.new_etl.__init__ import DATALAKE_QUERIES_DIR
from jobs.new_etl.crawlers.crawler_entity import CrawlerEntity
from qa_python_utils.default_logger import logger, _logger


class CrawlerCPFs(CrawlerEntity):

    def __init__(self, s3_bucket, google_maps_api_key):
        super(CrawlerCPFs, self).__init__(s3_bucket=s3_bucket, google_maps_api_key=google_maps_api_key)

    @logger(exclude='locations')
    def enrich(self, locations, cep=True):
        cols = ['location', 'gcep', 'glat', 'glng', 'gstreet', 'gstreet_number', 'gneighbourhood', 'gcity', 'gstate']
        info = pd.DataFrame([], columns=cols)

        loc = []
        for l in locations:
            r = self._get_address(cep=l) if cep else self._get_address(lat=l[0], lng=l[1])
            if r:
                s = pd.Series(index=cols)
                loc.append(l)
                s.glat = r[0].get('geometry', dict()).get('location', dict()).get('lat')
                s.glng = r[0].get('geometry', dict()).get('location', dict()).get('lng')
                for component in r[0].get('address_components', []):
                    if 'postal_code' in component.get('types', []):
                        s.gcep = component.get('short_name', '').replace('-', '')
                    if 'route' in component.get('types', []):
                        s.gstreet = component.get('short_name', '').replace('-', '')
                    if 'street_number' in component.get('types', []):
                        s.gstreet_number = component.get('short_name', '').replace('-', '')
                    if 'sublocality_level_1' in component.get('types', []):
                        s.gneighbourhood = component.get('short_name', '').replace('-', '')
                    if 'administrative_area_level_2' in component.get('types', []):
                        s.gcity = component.get('short_name', '').replace('-', '')
                    if 'administrative_area_level_1' in component.get('types', []):
                        s.gstate = component.get('short_name', '').replace('-', '')

                info = info.append(s, ignore_index=True)

        info.location = loc
        info.gcep = info.gcep.astype(int).astype(str).str.zfill(8)
        if cep:
            info.location = info.location.astype(int).astype(str).str.zfill(8)

        return info

    @logger(exclude='data')
    def fill_in(self, data):
        street_pattern = re.compile(r'-(.*)-n-(\d+)|-(.*)')
        data['street_name'] = data.street.apply(lambda x: CrawlerEntity._search_pattern(x, street_pattern, 1))
        data.street_name = data.street_name.combine_first(
            data.street.apply(lambda x: CrawlerEntity._search_pattern(x, street_pattern, 3)))
        data.street_name = data.street_name.apply(lambda x: x.replace('-', ' ') if x is not None else None)
        data['street_number'] = data.street.apply(lambda x: CrawlerEntity._search_pattern(x, street_pattern, 2))

        for i, row in data.query("""street_name.isnull() or street_number.isnull()""").iterrows():
            try:
                street, number = self.reverse_geocode(row.lat, row.lng)
                data.loc[i, 'street_name'] = ' '.join(street.split(' ')[1:])
                data.loc[i, 'street_number'] = number
            except Exception:
                _logger.warn('m=fill_in, could not retrieve street and number.')

        return data.query("""~street_name.isnull() and ~street_number.isnull()""")

    @logger
    def get_locations(self, ws, delta_days):
        last_date = datetime.strptime(self.get_last_crawling_date(ws), '%Y-%m-%d')
        since = last_date - timedelta(days=delta_days)

        q = BaseETL.get_query_from_file_name('{}/crawlers/get_locations.sql'.format(DATALAKE_QUERIES_DIR))
        q = q.format(ws=ws, started_on=last_date.strftime('%Y-%m-%d'), since=since.strftime('%Y-%m-%d'))

        locations = self.athena_client.execute_query_and_return_dataframe(q)
        if locations.empty:
            _logger.info('m=get_locations, msg=no locations to crawl')
            return None

        return locations

    @logger(exclude='locations')
    def check_locations_coverage(self, locations):
        # get to which region each lead belongs
        _logger.info('m=crawl_cpfs, checking coverage')
        locations['regions'] = locations.apply(lambda row: self.check_coverage(row.lat, row.lng), axis=1)
        # filter out units outside our coverage area
        locations = locations[
            (locations.regions > -1) & ((~locations.type.str.contains('casa')) |
                                        locations.regions.isin(self.house_allowed))]
        if locations.empty:
            _logger.info('m=get_locations, msg=no locations to crawl')
            return None

        return locations

    @logger(exclude='locations')
    def check_neighborhoods(self, locations, neighbourhood):
        if neighbourhood is None:
            return None

        neighbourhood = self.sanitize_text(neighbourhood)
        locations = locations[locations.neighborhood == neighbourhood]
        if locations.empty:
            _logger.info('m=get_locations, msg=no locations to crawl')
            return None

        return locations
