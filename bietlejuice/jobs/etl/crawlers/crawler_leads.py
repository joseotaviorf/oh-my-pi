# coding=utf-8

import json
from datetime import datetime, timedelta

import pandas as pd
import petl
from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.etl.crawlers.crawler_entity import CrawlerEntity

logger = QuintoAndarLogger('CrawlerLeads')


class CrawlerLeads(CrawlerEntity):
    LOGGER_CLASSNAME = "CrawlerLeads"

    QUEUE = 'CrawlerLeads'

    SOURCE_TYPE = {
        'zapimoveis': 'ZapImoveis',
        'olx': 'OLX',
        'imovelweb': 'ImovelWeb',
        'vivareal': 'VivaReal'
    }

    ORIGIN = 'Crawling'

    COLUMN_MAPPER = {
        'gcity': 'cidade',
        'advertiser_name': 'nomeAnunciante',
        'gstreet_number': 'numero',
        'phone_number': 'telefoneAnunciante',
        'gneighbourhood': 'bairro',
        'gstreet': 'endereco',
        'rent': 'valor',
        'updated_on': 'captadoEm',
        'complementary_info': 'infosExtras',
        'condominium': 'condominio',
        'bedrooms': 'numeroQuartos',
        'toilets': 'numeroBanheiros',
        'useful_area': 'areaTotal'
    }

    INFOS_TO_SEND = ['telefoneAnunciante', 'nomeAnunciante', 'numero', 'numeroQuartos', 'bairro', 'valor',
                     'numeroBanheiros', 'cidade', 'areaTotal', 'endereco', 'condominio', 'captadoEm',
                     'infosExtras', 'tipo', 'origem', 'cep', 'lat', 'lng', 'iptu']

    def __init__(self, s3_bucket, google_maps_api_key):
        super(CrawlerLeads, self).__init__(s3_bucket=s3_bucket, google_maps_api_key=google_maps_api_key)

    @logger
    def get_leads(self, ws, states, delta_days):
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

    @logger
    def check_known_phone(self, delta_days):
        q = BaseETL.get_query_from_file_name('{}/crawlers/get_known_phones.sql'.format(DATALAKE_QUERIES_DIR))

        since = datetime.today() - timedelta(days=delta_days)
        q = q.format(since=since.strftime('%Y-%m-%d'))

        phones = petl.todataframe(BaseETL.from_db_query(db_enum=EnumDB.QuintoAndar_ebdb, query=q))
        return phones.sort_values(by=['created_date'], ascending=False).drop_duplicates(subset=['phone_number'])

    @logger(exclude='leads')
    def send_leads(self, leads, ws):
        leads['origem'] = CrawlerLeads.ORIGIN
        leads['tipo'] = CrawlerLeads.SOURCE_TYPE[ws]
        leads['complementary_info'] = leads.apply(lambda row: ' - '.join([str(row.type), str(row.url)]), axis=1)

        # replacing None for Nan in the dataframe
        leads = leads.where((pd.notnull(leads)), None)

        to_send = leads.rename(columns=CrawlerLeads.COLUMN_MAPPER)[CrawlerLeads.INFOS_TO_SEND]

        messages = [json.dumps(j) for j in to_send.reset_index(drop=True).to_dict('records')]

        logger.info(
            'm={}.send_leads, msg=sending the following {} leads to the CrawlerLeads SQS.'.format(
                self.LOGGER_CLASSNAME, len(messages)))
        for message in messages:
            logger.info(
                'm={}.send_leads, msg={}.'.format(
                    self.LOGGER_CLASSNAME, message))

        BaseETL.publish_messages(messages=messages, queue_name=CrawlerLeads.QUEUE)
