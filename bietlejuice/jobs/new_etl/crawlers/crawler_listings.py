# coding=utf-8

import cStringIO
import csv
import itertools
from datetime import datetime

import fastparquet as fp
import numpy as np
import pandas as pd
import s3fs

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.new_etl import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.new_etl.crawlers.crawler_entity import CrawlerEntity
from qa_python_utils import QuintoAndarLogger

logger = QuintoAndarLogger('CrawlerListings')


class CrawlerListings(CrawlerEntity):
    CLEAN_COLUMNS = ['id', 'website', 'street', 'street_number', 'neighborhood', 'city', 'state', 'lat', 'lng',
                     'latlng', 'full_address', 'location_type', 'location_precision', 'gcep', 'glat', 'glng', 'gstreet',
                     'gaddress_flg', 'dt_gaddress', 'gstreet_number', 'gneighborhood', 'gcity', 'gstate', 'street_flg',
                     'street_number_flg', 'neighborhood_flg', 'cep_flg', 'city_flg', 'latlng_flg', 'full_address_flg',
                     'primary_phone_number', 'secondary_phone_number', 'price', 'rent', 'condominium', 'iptu',
                     'total_area', 'useful_area', 'bedrooms', 'suites', 'toilets', 'garages', 'year_building', 'cep',
                     'sk_date_updated_on', 'sk_date_last_run', 'sk_date_first_seen', 'sk_date_last_seen', 'active',
                     'days_seen', 'days_unseen', 'runs_unseen', 'rental_flg', 'sale_flg', 'listing_type',
                     'advertiser_type', 'big_advertiser', 'advertiser_name', 'o_lat', 'o_lng', 'sk_region']

    LOCATION_COLUMNS = ['id', 'website', 'glat', 'glng', 'gcep', 'gstreet', 'gstreet_number', 'gneighborhood', 'gcity',
                        'gstate', 'location_type', 'location_precision', 'dt_gaddress']

    @logger
    def __init__(self, s3_bucket, google_maps_api_key, google_maps_daily_quota, max_batch_size):
        super(CrawlerListings, self).__init__(
            s3_bucket=s3_bucket,
            google_maps_api_key=google_maps_api_key,
            get_polygons=True,
            get_house_allowed=False
        )
        self.max_batch_size = int(max_batch_size)
        self.google_maps_daily_quota = google_maps_daily_quota
        self.listings = pd.DataFrame([], columns=self.CLEAN_COLUMNS)
        self.latlngs = pd.DataFrame([], columns=['lat', 'lng'])
        self.addresses = pd.DataFrame([], columns=['full_address'])
        self.new_locations = pd.DataFrame([], columns=self.LOCATION_COLUMNS)
        daily_gaddress_count = self.get_daily_gaddress_count()
        daily_quota = google_maps_daily_quota if type(google_maps_daily_quota) == 'int' else int(
            google_maps_daily_quota)
        self.api_quota = daily_quota - daily_gaddress_count
        self.api_quota = self.api_quota if self.api_quota > 0 else 0
        self.page_count = 0
        self.page_size = 1000  # this is the APIs max allowed value
        if self.api_quota == 0:
            logger.warning('Number of daily requests reached the daily quota')

    def get_crawler_listings(self):
        return self.listings

    def get_crawler_latlngs(self):
        return self.latlngs

    def get_crawler_addresses(self):
        return self.addresses

    def add_5a_regions(self):
        self.listings['sk_region'] = self.listings.apply(lambda row: self.check_coverage(row['o_lat'], row['o_lng']),
                                                         axis=1)

    def coalesce_lat_lngs(self):
        self.listings['o_lat'] = self.listings['glat'].combine_first(self.listings['lat']).astype('float').round(4)
        self.listings['o_lng'] = self.listings['glng'].combine_first(self.listings['lng']).astype('float').round(4)

    def get_daily_gaddress_count(self):
        ''' Get how many addresses were added to the DB today to avoid breaking the defined quota '''

        query = BaseETL.get_query_from_file_name(
            '{}/crawlers/get_daily_gaddress_count.sql'.format(DATALAKE_QUERIES_DIR))
        if not query:
            return None
        df = self.athena_client.execute_query_and_return_dataframe(query)
        return df.daily_total.values[0]

    def get_crawler_locations(self):
        ''' Get how many addresses were added to the DB today to avoid breaking the defined quota '''

        query = BaseETL.get_query_from_file_name('{}/crawlers/get_crawler_locations.sql'.format(DATALAKE_QUERIES_DIR))
        if not query:
            return None
        df = self.athena_client.execute_query_and_return_dataframe(query)
        return df

    # TODO: Move this to a Google Maps Wrapper
    @staticmethod
    def get_nearest_reverse_geocode_result(lat, lng, results):
        locations = [[r.get('geometry').get('location').get('lat'), r.get('geometry').get('location').get('lng')] for r
                     in results]
        dist = np.linalg.norm(np.array(locations) - np.array([lat, lng]), axis=1)
        return results[np.argmin(dist)]

    @logger
    def load_crawler_listings(self):
        ''' Get addresses attribution from the datalake and returns a dataframe '''

        # call crawler_listings query and return dataframe
        query = BaseETL.get_query_from_file_name('{}/crawlers/get_crawled_listings.sql'.format(DATALAKE_QUERIES_DIR))
        if not query:
            return None
        return self.athena_client.execute_query_and_return_dataframe(sql=query, paginate=True, page_size=self.page_size)

    @logger
    def clean_listings(self):
        # cleaning and merging new addresses
        for column in self.listings.columns:
            self.listings[column] = self.listings[column].apply(lambda x: x if x != '' else None)
            if '_flg' in column:
                self.listings[column] = self.listings[column].apply(lambda x: True if x == 'true' else False)
        self.listings = self.cleaning(self.listings, ['advertiser_name', 'listing_type'])
        self.latlngs = self.listings[
            self.listings['latlng_flg'].astype('bool') &
            ~self.listings['full_address_flg'].astype(bool) &
            ~self.listings['gaddress_flg'].astype(bool)
        ][['lat', 'lng']].drop_duplicates()
        self.addresses = self.listings[
            ~self.listings['latlng_flg'].astype('bool') &
            ~self.listings['full_address_flg'].astype(bool) &
            ~self.listings['gaddress_flg'].astype(bool)
        ]['full_address'].drop_duplicates()

    @logger(exclude='entity')
    def enrich(self, entity, cep=False, location_type=False, reverse=True):
        cols = ['gcep', 'glat', 'glng', 'gstreet', 'gstreet_number', 'gneighborhood', 'gcity', 'gstate',
                'location_type', 'location_precision', 'dt_gaddress']
        info = pd.DataFrame([], columns=cols)
        dt_gaddress = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        info['location'] = None

        iter_count = self.api_quota
        logger.info('m=enrich, quota={}, entity_size={}, starting to call api'.format(self.api_quota, len(entity)))
        for l in itertools.islice(entity, self.api_quota):
            r = self._get_address(lat=l[0], lng=l[1]) if reverse else self._get_address(raw_address=l)
            iter_count -= 1
            if r:
                s = pd.Series(index=cols)
                location = '{0},{1}'.format(l[0], l[1]) if reverse else l
                nearest = self.get_nearest_reverse_geocode_result(l[0], l[1], r) if reverse else r[0]

                s.glat = nearest.get('geometry', dict()).get('location', dict()).get('lat', None)
                s.glng = nearest.get('geometry', dict()).get('location', dict()).get('lng', None)
                s.location_precision = nearest.get('geometry', dict()).get('location_type', None)
                s.location_type = 'latlng' if reverse else 'raw_address'

                for component in nearest.get('address_components', []):
                    if 'postal_code' in component.get('types', []):
                        s.gcep = component.get('short_name', None).replace('-', '')
                    if 'route' in component.get('types', []):
                        s.gstreet = component.get('short_name', None).replace('-', '')
                    if 'street_number' in component.get('types', []):
                        s.gstreet_number = component.get('short_name', None).replace('-', '')
                    if 'sublocality_level_1' in component.get('types', []):
                        s.gneighborhood = component.get('short_name', None).replace('-', '')
                    if 'administrative_area_level_2' in component.get('types', []):
                        s.gcity = component.get('short_name', None).replace('-', '')
                    if 'administrative_area_level_1' in component.get('types', []):
                        s.gstate = component.get('short_name', None).replace('-', '')
                s['location'] = location
                s['dt_gaddress'] = dt_gaddress
                info = info.append(s, ignore_index=True)

            if iter_count % 100 == 0:
                logger.info('m=enrich, iterated={}, continuing iteration'.format(self.api_quota - iter_count))
        self.api_quota = iter_count
        logger.info('m=enrich, quota_left={}, finished iterating'.format(self.api_quota))
        info.gcep = info.gcep.astype(str).str.zfill(8)
        info.gcep = info.gcep.replace({'00000nan': None})

        join_key = 'latlng' if reverse else 'full_address'
        self.listings = pd.merge(self.listings, info, how='left', left_on=join_key, right_on='location',
                                 suffixes=('', '_new'))
        for col in cols:
            col_new = '{}_new'.format(col)
            self.listings[col] = self.listings[col].where(self.listings[col] != '', None)
            self.listings[col] = self.listings[col].combine_first(self.listings[col_new])
            self.listings.drop([col_new], axis=1, inplace=True)
        self.listings.drop(['location'], axis=1, inplace=True)

    @logger
    def merge_new_addresses(self):
        new_locations = \
            self.listings[
                ~self.listings['full_address_flg'].astype(bool) &
                ~self.listings['gaddress_flg'].astype(bool) &
                ~self.listings['glat'].where(self.listings['glat'] != '', None).isnull()
            ][self.LOCATION_COLUMNS]
        logger.info('m=merge_new_addresses, msg=merging {} new locations to {} current'.format(
            new_locations.shape, self.new_locations.shape))
        self.new_locations = self.new_locations.append(new_locations.where(~new_locations.isnull(), ''))

    @logger
    def persist_address_attribution(self):
        ''' Persist new attributions to the datalake '''
        if len(self.new_locations) != 0:
            current_locations = self.get_crawler_locations()

            output = current_locations.append(self.new_locations).drop_duplicates()

            filename = 'crawler_locations'
            logger.info('m=persist_address_attribution, msg=merged new locations{} with current locations{}'.format(
                self.new_locations.shape, current_locations.shape))
            obj = output.to_csv(index=False, encoding='utf8', quoting=csv.QUOTE_NONNUMERIC)
            io = cStringIO.StringIO(obj)
            BaseETL.obj_to_s3(
                obj_io=io,
                bucket=self.bucket,
                file_path='raw/{0}/{0}.csv'.format(filename)
            )
        else:
            logger.info('m=persist_address_attribution, msg=no new locations to persist')

    @logger
    def persist_clean_crawler_data(self):
        filename = 'crawler_listings'
        file_path = 'clean/{0}/{0}-part{1}.parq'.format(filename, self.page_count)
        for column in self.CLEAN_COLUMNS:
            self.listings[column] = self.listings[column].fillna('').astype(str)
        s3_fs = s3fs.S3FileSystem()
        logger.info('m=persist_clean_crawler_data, msg=ready to upload')
        fp.write(
            '{}/{}'.format(self.bucket, file_path),
            self.listings[self.CLEAN_COLUMNS],
            open_with=s3_fs.open
        )
        logger.info('m=persist_clean_crawler_data, msg={} ready on s3'.format(file_path))

    @logger
    def enrich_crawler_addresses(self):
        new_latlng = self.get_crawler_latlngs()
        new_addresses = self.get_crawler_addresses()
        self.enrich(new_latlng.values)
        self.enrich(new_addresses.values, reverse=False)

    @logger
    def transform_crawler_data(self):
        self.clean_listings()
        self.enrich_crawler_addresses()
        self.merge_new_addresses()
        self.coalesce_lat_lngs()
        self.add_5a_regions()
        self.persist_clean_crawler_data()
        self.listings = pd.DataFrame([], columns=self.CLEAN_COLUMNS)

    @logger
    def iterate_crawler_data(self):
        gen = self.load_crawler_listings()
        current_batch_size = 0
        for i, df in enumerate(gen):
            current_batch_size += self.page_size
            batch_size = len(df) if i > 0 else len(df) + 1
            self.listings = self.listings.append(df)
            logger.info('m=iterate_crawler_data, msg=max batch size {}'.format(self.max_batch_size))
            logger.info('m=iterate_crawler_data, msg=current df size {}'.format(self.listings.shape))
            logger.info('m=iterate_crawler_data, msg=current batch size {}'.format(current_batch_size))
            if (current_batch_size >= self.max_batch_size) or (batch_size < self.page_size):
                self.transform_crawler_data()
                self.page_count += 1
                current_batch_size = 0
        self.persist_address_attribution()
