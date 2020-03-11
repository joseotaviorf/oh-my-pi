# encoding: utf-8
import re
import sys
from collections import OrderedDict

import pandas as pd
import petl
from elasticsearch import Elasticsearch
from elasticsearch import helpers
from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.base.enum_db import EnumDB

reload(sys)
sys.setdefaultencoding('utf8')

logger = QuintoAndarLogger('HelpCenter')


class HelpCenter(object):
    """
    Search user (exact):
        GET /user/_search?q=phone[:|=]"11111111"
        GET /user/_search?q=phone[:|=]"11111111" [and | or] email="a@b.c"

    Search user (like):
        GET /user/_search?q=phone[:|=]11111111
        GET /user/_search?q=phone[:|=]11111111 [and | or] email=a@b.c
    """

    @logger
    def __init__(self, es_host):
        self.es = Elasticsearch([es_host])

    @logger
    def get_user_info(self):
        query = BaseETL.get_query_from_file_name('{}/user_information.sql'.format(DATALAKE_QUERIES_DIR))
        table = BaseETL.from_db_query(
            query=query,
            db_enum=EnumDB.BI_DW,
        )

        return petl.todataframe(table)

    @logger
    def get_data_from_elasticsearch(self, phone, email):
        result = self.es.search(index='users', params={'q': 'phone:{0}&email:{1}'.format(phone, email)})['hits']
        hits = result['hits']
        if len(hits) == 0:
            return

        for hit in hits:
            logger.info(hit['_source'])

    @logger
    def clean_elasticsearch(self):
        success = False
        while not success:
            try:
                response = self.es.delete_by_query(index='hc-users', body={'query': {'match_all': dict()}})
                success = not response['timed_out'] and len(response['failures']) == 0
            except Exception as e:
                logger.error('m=clean_elasticsearch, message_error={}'.format(e.message))

    @logger(exclude='df_user')
    def send_data_to_elasticsearch(self, df_user):
        df_user = df_user.astype(object).where(pd.notnull(df_user), None)

        actions = []
        for _, user_row in df_user.iterrows():
            actions.append({
                '_op_type': 'index',
                '_index': 'hc-users',
                '_type': 'user',
                '_source': {
                    'quintoandar_id': str(user_row['quintoandar_id']) if user_row['quintoandar_id'] else None,
                    'email': user_row['email'] if user_row['email'] and user_row['email'] != '' else None,
                    'roles': self.__split_and_filter(user_row['roles']),
                    'names': self.__split_and_filter(user_row['names'].encode('utf8') if user_row['names'] else None),
                    'phones': self.__split_and_filter(field_list=user_row['phones'] if user_row['phones'] else None,
                                                      regex_pattern='[^+\d]',
                                                      regex_replace=''),
                    'zendesk_ids': self.__split_and_filter(user_row['zendesk_ids']),
                    'amplitude_ids': self.__split_and_filter(user_row['amplitude_ids'])
                }
            })

        result = helpers.bulk(self.es, actions)
        logger.error('m=send_data_to_elasticsearch, data_sent={}'.format(result[0]))

        if len(result[1]) > 0:
            logger.error('m=send_data_to_elasticsearch, errors={}'.format(result[1]))

    @classmethod
    def __split_and_filter(cls, field_list, regex_pattern=None, regex_replace=None):
        if field_list is None:
            return None

        if regex_pattern is not None and regex_replace is not None:
            result = [re.sub(regex_pattern, regex_replace, '+55' + f if '+55' not in f and f != '' else f).strip()
                      for f in field_list.split(',')]
        else:
            result = field_list.split(',')

        return filter(None, OrderedDict.fromkeys(result).keys())
