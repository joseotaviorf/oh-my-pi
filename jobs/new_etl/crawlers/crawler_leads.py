# coding=utf-8

import json
import locale
import re
from datetime import datetime, timedelta

import numpy as np
from qa_python_utils.default_logger import logger

from jobs.base.base_etl import BaseETL
from jobs.new_etl.__init__ import DATALAKE_QUERIES_DIR
from jobs.new_etl.crawlers.crawler_entity import CrawlerEntity


class CrawlerLeads(CrawlerEntity):
    QUEUE = 'CrawlerLeads'

    SOURCE_TYPE = {
        'zapimoveis': 'ZapImoveis',
        'olx': 'OLX',
        'imovelweb': 'ImovelWeb',
        'vivareal': 'VivaReal'
    }

    ORIGIN = 'Crawling'

    COLUMN_MAPPER = {
        'gcep': 'cep',
        'gcity': 'cidade',
        'advertiser_name': 'nomeAnunciante',
        'gstreet_number': 'numero',
        'phones': 'telefoneAnunciante',
        'gneighbourhood': 'bairro',
        'gstreet': 'endereco',
        'rent': 'valor',
        'updated_on': 'captadoEm',
        'complementary_info': 'infosExtras'
    }

    INFOS_TO_SEND = ['captadoEm', 'tipo', 'origem', 'cep', 'cidade', 'bairro', 'endereco', 'numero', 'lat', 'lng',
                     'valor', 'nomeAnunciante', 'telefoneAnunciante', 'infosExtras']

    def __init__(self, s3_bucket, google_maps_api_key):
        super(CrawlerLeads, self).__init__(s3_bucket=s3_bucket, google_maps_api_key=google_maps_api_key)

    @logger
    def leads(self, ws, states, delta_days):
        q = BaseETL.get_query_from_file_name('{}/crawlers/get_leads.sql'.format(DATALAKE_QUERIES_DIR))
        if not q:
            return None

        last_date = datetime.strptime(self.get_last_crawling_date(ws), '%Y-%m-%d')
        since = last_date - timedelta(days=delta_days)

        q = q.format(
            started_on=last_date.strftime('%Y-%m-%d'),
            ws=ws,
            since=since.strftime('%Y-%m-%d'),
            states="', '".join(states).lower()
        )

        return self.athena_client.execute_query_and_return_dataframe(q)

    @logger(exclude='leads')
    def check_known_phone(self, leads, delta_days):
        q = BaseETL.get_query_from_file_name('{}/crawlers/get_known_phones.sql'.format(DATALAKE_QUERIES_DIR))

        phone_list = "', '".join(
            [re.sub(r'\+\d{2}|[(|)]', '', str(p))
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
        leads.gcep = leads.gcep.replace({'00000nan': None}).combine_first(leads.cep)

        leads = leads.drop(labels=['cep'], axis=1)

        leads.phones = leads.phones.apply(lambda p: eval(p)[0])
        leads = leads.drop_duplicates(subset=['phones'])
        leads = leads[leads.phones.astype(str).str.len() >= 11]

        locale.setlocale(locale.LC_MONETARY, '')
        leads.rent = leads.rent.apply(lambda p: locale.currency(p) if not np.isnan(p) else None)

        leads.gstreet_number = leads.gstreet_number.where(
            ~leads.gstreet_number.isnull(), None).astype(str).str.slice(stop=-2)
        leads['origem'] = CrawlerLeads.ORIGIN
        leads['tipo'] = CrawlerLeads.SOURCE_TYPE[ws]
        leads['complementary_info'] = leads.apply(lambda row: ' - '.join([str(row.id), str(row.url)]), axis=1)

        to_send = leads.rename(columns=CrawlerLeads.COLUMN_MAPPER)[CrawlerLeads.INFOS_TO_SEND]

        messages = [json.dumps(j) for j in to_send.reset_index(drop=True).to_dict('records')]

        BaseETL.publish_messages(messages=messages, queue_name=CrawlerLeads.QUEUE)
