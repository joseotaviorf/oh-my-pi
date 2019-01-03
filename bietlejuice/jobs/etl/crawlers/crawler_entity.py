# coding=utf-8

import re

import googlemaps
import numpy as np
import pandas as pd
import requests
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient
from shapely import wkt
from shapely.geometry import Point
from unidecode import unidecode

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR

logger = QuintoAndarLogger('CrawlerEntity')


class CrawlerEntity(object):

    def __init__(self, s3_bucket, google_maps_api_key, get_polygons=True, get_house_allowed=True):
        self.athena_client = AthenaClient(s3_bucket)
        self.bucket = s3_bucket
        if google_maps_api_key is not None:
            self.gmaps_client = googlemaps.Client(key=google_maps_api_key)
            self.google_maps_api_key = google_maps_api_key

        types_apto = ['apartamento-padrao', 'apartamento', 'aluguel-apartamento-duplex-triplex',
                      'aluguel-apartamento-padrao', 'venda-apartamento-padrao', 'aluguel-apartamento', 'apartment']
        types_casa = ['casa-padrao', 'aluguel-casa', 'aluguel-casa-em-rua-publica', 'aluguel-casa-em-vila',
                      'venda-casa-em-rua-publica', 'venda-casa-em-vila', 'home', 'two_story_house']
        types_cond = ['casa-de-condominio', 'aluguel-casa-em-condominio-fechado', 'venda-casa-em-condominio-fechado',
                      'condominium']
        types_pent = ['cobertura', 'aluguel-apartamento-cobertura', 'venda-apartamento-cobertura',
                      'aluguel-apartamento-duplex-triplex', 'penthouse']
        types_flat = ['flat']
        types_kiti = ['loft', 'studio', 'aluguel-apartamento-kitchenette', 'aluguel-loft-studio', 'kitnet']
        map_types = {k: 'apartamento' for k in types_apto}
        map_types.update({k: 'casa' for k in types_casa})
        map_types.update({k: 'casa-condominio' for k in types_cond})
        map_types.update({k: 'cobertura' for k in types_pent})
        map_types.update({k: 'flat' for k in types_flat})
        map_types.update({k: 'loft-studio-kitchenette' for k in types_kiti})
        self.map_types = map_types

        if get_polygons is True:
            self.polygons = self.__get_polygons()

        if get_house_allowed is True:
            q = BaseETL.get_query_from_file_name('{}/crawlers/get_house_allowed_ids.sql'.format(DATALAKE_QUERIES_DIR))
            self.house_allowed = self.athena_client.execute_query_and_return_dataframe(q).id.tolist()

    def _get_address(self, lat=None, lng=None, cep=None, raw_address=None):
        r = None
        if lat is not None and lng is not None:
            r = self.gmaps_client.reverse_geocode((lat, lng))
        elif cep is not None:
            r = self.gmaps_client.geocode('cep {}'.format(cep))
        elif raw_address is not None:
            r = self.gmaps_client.geocode('{}'.format(raw_address))

        return r

    @staticmethod
    def sanitize_text(s):
        if s is not None:
            u = unidecode(unicode(s))
            return '-'.join(re.sub("[^\w]", " ", u).split()).lower()

        return None

    def __get_crawling_dates(self):
        q = """show partitions datalake_raw.crawlers"""
        partitions = self.athena_client.execute_txt_query_and_return_dataframe(q)
        pattern = re.compile(r'ws=(\D+)\/started_on=(\d{4}-\d{2}-\d{2})')
        partitions = pd.DataFrame(
            [pattern.search(p[0]).groups() for p in partitions.values],
            columns=['ws', 'started_on']
        )
        return partitions

    def get_last_crawling_date(self, ws):
        partitions = self.__get_crawling_dates()
        return partitions.loc[partitions.ws == ws, 'started_on'].max()

    def __get_polygons(self):
        q = BaseETL.get_query_from_file_name('{}/crawlers/get_polygons.sql'.format(DATALAKE_QUERIES_DIR))
        if not q:
            return None

        polygons = self.athena_client.execute_query_and_return_dataframe(q)

        polygons.region = polygons.region.apply(self.sanitize_text)
        polygons.city = polygons.city.apply(self.sanitize_text)
        polygons.poly = polygons.poly.apply(wkt.loads)

        return polygons

    @logger(exclude='entity')
    def cleaning(self, entity, columns=None):
        if columns:
            text_columns = columns
        else:
            text_columns = ['type', 'advertiser_name', 'street', 'neighborhood', 'city', 'state', 'listing_type']
        for c in text_columns:
            if c in entity:
                entity[c] = entity[c].apply(self.sanitize_text)

        if 'cep' in entity:
            entity.cep = entity.cep.astype(str).str.zfill(8)
        if 'type' in entity:
            entity.type = entity.type.replace(self.map_types)
        if 'listing_type' in entity:
            entity.listing_type = entity.listing_type.replace(self.map_types)

        num_columns = ['rent', 'lat', 'lng']
        for c in num_columns:
            if c in entity:
                if any([isinstance(v, basestring) for v in entity[c]]):
                    entity[c].replace({'': np.nan}, inplace=True)
                    entity[c] = entity[c].astype(float)

        return entity

    def check_coverage(self, lat, lng):
        p = Point((lng, lat))

        for _, row in self.polygons.iterrows():
            if row.poly.contains(p):
                return row.id

        return -1

    @logger(exclude='entity')
    def enrich(self, entity, cep=True, location_type=False):
        cols = ['location', 'gcep', 'glat', 'glng', 'gstreet', 'gstreet_number', 'gneighbourhood', 'gcity', 'gstate']
        info = pd.DataFrame([], columns=cols)

        loc = []
        for l in entity:
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
        info.gcep = info.gcep.astype(str).str.zfill(8)
        if cep:
            info.location = info.location.astype(int).astype(str).str.zfill(8)

        return info

    @staticmethod
    @logger
    def _search_pattern(string, pattern, group=0):
        try:
            return pattern.search(string).group(group)
        except Exception:
            return None

    @logger
    def reverse_geocode(self, lat, lng):
        params = {
            'key': self.google_maps_api_key,
            'latlng': "%f,%f" % (lat, lng),
            'sensor': 'false',
            'result_type': 'street_address|street_number',
            'location_type': 'ROOFTOP'
        }
        page = requests.get('https://maps.googleapis.com/maps/api/geocode/json', params=params).json()
        try:
            addr = page['results'][0]['address_components']
            route = self._get_long_name(addr, 'route')
            number = self._get_long_name(addr, 'street_number')
            return route, number
        except Exception:
            logger.warning('m=reverse_geocode, maps api response has no address components')

    @staticmethod
    def _get_long_name(addr, addr_type):
        for component in addr:
            if addr_type in component['types']:
                return component['long_name']
