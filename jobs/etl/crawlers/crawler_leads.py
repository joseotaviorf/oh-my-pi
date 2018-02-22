# coding=utf-8

import argparse
import json
import locale
import os
import re
from datetime import datetime, timedelta

import googlemaps
import numpy as np
import pandas as pd
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import logger
from shapely import wkt
from shapely.geometry import Point
from unidecode import unidecode

from jobs.base.base_etl import BaseETL


class CrawlerLeads(object):
    QUEUE = 'CrawlerLeads'
    SOURCE_TYPE = {
        'zapimoveis': 'ZapImoveis',
        'olx': 'OLX',
        'imovelweb': 'ImovelWeb',
        'vivareal': 'VivaReal'
    }
    ORIGIN = 'Crawling'

    BUCKET = os.environ['bi-datalake-s3-bucket']
    GOOGLE_MAPS_API_KEY = os.environ['crawler-gmaps-key']

    HERE = os.path.dirname(os.path.realpath(__file__))

    COLUMN_MAPPER = {'gcep': 'cep',
                     'gcity': 'cidade',
                     'advertiser_name': 'nomeAnunciante',
                     'gstreet_number': 'numero',
                     'phones': 'telefoneAnunciante',
                     'gneighbourhood': 'bairro',
                     'gstreet': 'endereco',
                     'rent': 'valor',
                     'updated_on': 'captadoEm',
                     'complementary_info': 'infosExtras'}

    INFOS_TO_SEND = ['captadoEm', 'tipo', 'cep', 'cidade', 'bairro', 'endereco', 'numero', 'lat', 'lng', 'valor',
                     'nomeAnunciante', 'telefoneAnunciante', 'infosExtras']

    def __init__(self):
        self.athena_client = AthenaClient(self.BUCKET)
        self.gmaps_client = googlemaps.Client(key=self.GOOGLE_MAPS_API_KEY)

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

        self.polygons = None
        self._get_polygons()

        with open(os.path.join(self.HERE, 'queries/get_house_allowed_ids.sql'), 'r') as f:
            q = f.read()
        self.house_allowed = self.athena_client.execute_query_and_return_dataframe(q).id.tolist()

    def _get_address(self, lat=None, lng=None, cep=None):
        r = None
        if lat is not None and lng is not None:
            r = self.gmaps_client.reverse_geocode((lat, lng))
        elif cep is not None:
            r = self.gmaps_client.geocode('cep {}'.format(cep))

        return r

    @staticmethod
    def _sanitize_text(s):
        if s is not None:
            u = unidecode(unicode(s))
            return '-'.join(re.sub("[^\w]", " ", u).split()).lower()

        return None

    def _get_crawling_dates(self):
        q = """show partitions datalake_raw.crawlers"""
        partitions = self.athena_client.execute_txt_query_and_return_dataframe(q)
        pattern = re.compile(r'ws=(\D+)\/started_on=(\d{4}-\d{2}-\d{2})')
        partitions = pd.DataFrame(
            [pattern.search(p[0]).groups() for p in partitions.values],
            columns=['ws', 'started_on']
        )
        return partitions

    def _get_last_crawling_date(self, ws):
        partitions = self._get_crawling_dates()
        return partitions.loc[partitions.ws == ws, 'started_on'].max()

    def _get_polygons(self):
        with open(os.path.join(self.HERE, 'queries/get_polygons.sql'), 'r') as f:
            q = f.read()

        polygons = self.athena_client.execute_query_and_return_dataframe(q)

        polygons.region = polygons.region.apply(self._sanitize_text)
        polygons.city = polygons.city.apply(self._sanitize_text)
        polygons.poly = polygons.poly.apply(wkt.loads)

        self.polygons = polygons

    @logger
    def leads(self, ws, states, delta_days):
        with open(os.path.join(self.HERE, 'queries/get_leads.sql'), 'r') as f:
            q = f.read()

        leads = None
        if q:
            last_date = datetime.strptime(self._get_last_crawling_date(ws), '%Y-%m-%d')
            since = last_date - timedelta(days=delta_days)

            q = q.format(
                started_on=last_date.strftime('%Y-%m-%d'),
                ws=ws,
                since=since.strftime('%Y-%m-%d'),
                states="', '".join(states).lower())

            leads = self.athena_client.execute_query_and_return_dataframe(q)

        return leads

    @logger(exclude='leads')
    def cleaning(self, leads):
        text_columns = ['type', 'advertiser_name', 'street', 'neighborhood', 'city', 'state']
        for c in text_columns:
            leads[c] = leads[c].apply(self._sanitize_text)

        leads.cep = leads.cep.astype(str).str.zfill(8)
        leads.type = leads.type.replace(self.map_types)

        num_columns = ['rent', 'lat', 'lng']
        for c in num_columns:
            if any([isinstance(v, basestring) for v in leads[c]]):
                leads[c].replace({'': np.nan}, inplace=True)
            leads[c] = leads[c].astype(float)

        return leads

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

    def check_coverage(self, lat, lng):
        p = Point((lng, lat))

        for _, row in self.polygons.iterrows():
            if row.poly.contains(p):
                return row.id

        return -1

    @logger(exclude='leads')
    def check_known_phone(self, leads, delta_days):
        with open(os.path.join(self.HERE, 'queries/get_known_phones.sql'), 'r') as f:
            q = f.read()
        phone_list = "', '".join(
            [re.sub('\+\d{2}|[(|)]', '', str(p))
             for p in np.array([np.array(p) for p in leads.phones.apply(eval).values]).ravel()])
        since = datetime.today() - timedelta(days=delta_days)
        q = q.format(phone_list=phone_list, since=since.strftime('%Y-%m-%d'))

        phones = self.athena_client.execute_query_and_return_dataframe(q)
        phones.phone_number = phones.phone_number.astype(str).str.slice(2)
        return phones.sort_values(by=['created_date'], ascending=False).drop_duplicates(subset=['phone_number'])

    @logger(exclude='leads')
    def send_leads(self, leads, ws):
        leads['location'] = leads.apply(lambda row: (row.lat, row.lng), axis=1)
        info = self.enrich(leads.location.values, cep=False)

        gcolumns = info.columns[info.columns.str.startswith('g')]
        leads = leads.loc[:, ~leads.columns.isin(gcolumns)].merge(info, how='left', on='location')
        leads.phones = leads.phones.apply(lambda p: eval(p)[0])

        locale.setlocale(locale.LC_MONETARY, '')
        leads.rent = leads.rent.apply(lambda p: locale.currency(p) if not np.isnan(p) else None)

        leads.gstreet_number = leads.gstreet_number.where(
            ~leads.gstreet_number.isnull(), None).astype(str).str.slice(stop=-2)
        leads['origem'] = 'Crawling'
        leads['tipo'] = self.SOURCE_TYPE[ws]
        leads['complementary_info'] = leads.apply(lambda row: ' - '.join([str(row.id), str(row.url)]), axis=1)

        to_send = leads.rename(columns=self.COLUMN_MAPPER)[self.INFOS_TO_SEND]

        messages = [json.dumps(j) for j in to_send.reset_index(drop=True).to_dict('records')]

        BaseETL.publish_messages(messages=messages, queue_name=self.QUEUE)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()

    parser.add_argument('--max', action='store', default=1, type=int, help='Max number of leads to be sent.')
    parser.add_argument('--ws', action='store', default='olx', help='Website from where we get leads.')
    parser.add_argument('--states', type=str, nargs='*', default=[], help='State or list of states to get leads.')
    parser.add_argument(
        '--since', action='store', default=2, type=int, help='Difference in days between crawled_on and updated_on')
    args = parser.parse_args()

    crawler_leads = CrawlerLeads()
    leads = crawler_leads.leads(ws=args.ws, states=args.states, delta_days=args.since)
    leads = crawler_leads.cleaning(leads)

    # enrich lat and lng with ceps
    info = crawler_leads.enrich(leads.query("""lat.isnull() or lng.isnull()""").cep.unique())
    leads = leads.merge(info, how='left', left_on='cep', right_on='location')
    leads.lat = leads.lat.combine_first(leads.glat)
    leads.lng = leads.lng.combine_first(leads.glng)

    # get to which region each lead belongs
    leads['regions'] = leads.apply(lambda row: crawler_leads.check_coverage(row.lat, row.lng), axis=1)

    # filter out units outside our coverage area
    leads = leads[(leads.regions > -1) & ((leads.type != 'casa') | leads.regions.isin(crawler_leads.house_allowed))]

    # get known phones from last 6 months
    phones = crawler_leads.check_known_phone(leads, delta_days=180)
    leads['known'] = pd.Series(
        np.array([np.array(p) for p in leads.phones.apply(eval).values]).ravel()).isin(
        phones.phone_number.unique()).values

    # send leads not known
    crawler_leads.send_leads(leads[~leads.known], ws='olx')
