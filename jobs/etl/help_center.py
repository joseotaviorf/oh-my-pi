import json
import os
import re
import sys

import pandas as pd
import petl
from elasticsearch import Elasticsearch
from elasticsearch import helpers
from jobs.base.base_etl import BaseETL
from jobs.base.enum_db import EnumDb
from qa_python_utils.default_logger import logger, _logger

args = sys.argv
help_center = json.loads(os.environ['help-center'])


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
    def __init__(self):
        self.es = Elasticsearch([help_center['elasticsearch-host']])

    @logger
    def get_user_info(self):
        table = BaseETL.from_db_query(
            query="""with ns as (
                        select 1 as n
                        union all
                        select 2
                        union all
                        select 3
                        union all
                        select 4
                        union all
                        select 5
                        union all
                        select 6
                        union all
                        select 7
                        union all
                        select 8
                        union all
                        select 9
                        union all
                        select 10
                    ),
                    ns_c as (
                      select
                        trim(split_part(cp.email, ',', ns.n)) as email, cp.telefone, cp.nome
                      from ns
                        join datalake_clean.ebdb_contract_person cp
                          on ns.n <= regexp_count(cp.email, ',') + 1
                    ),
                    ns_p as (
                      select
                        trim(split_part(cp.email, ';', ns.n)) as email, cp.telefone, cp.nome
                      from ns
                        join datalake_clean.ebdb_contract_person cp
                          on ns.n <= regexp_count(cp.email, ';') + 1
                    ),
                    union_all as (
                      select email, telefone, nome
                      from ns_c
                        union all
                      select email, telefone, nome
                      from ns_p
                    ),
                    contrato_pessoa as (
                      select distinct trim(email) as email, telefone, nome
                      from union_all
                        where email is not null
                        and email != ''
                    ),
                    users as (
                      select distinct
                        coalesce(uc.email, up.email, cp.email, pp.email) as email,
                        coalesce(uc.telefoneprincipal, up.telefoneprincipal, cp.telefone, pp.telefone) as main_phone,
                        coalesce(uc.nome, up.nome, cp.nome) as name,
                        coalesce(up.id, uc.id, null) as id
                      from contrato_pessoa cp
                        full outer join datalake_clean.ebdb_proponent_proposal pp
                          on pp.email = cp.email
                        full outer join datalake_clean.ebdb_user up
                          on up.email = pp.email
                        full outer join datalake_clean.ebdb_user uc
                          on uc.email = cp.email
                    ),
                    all_info as (
                      select distinct
                        us.id as quintoandar_id,
                        trim(us.email) as email,
                        trim(us.name) as "name",
                        trim(us.main_phone) as phone,
                        mu.amplitude_id as amplitude_id,
                        zu.id as zendesk_id,
                        astk.caller_number as asterisk_id
                      from users us
                        left join amplitude_events.merged_users mu
                          on us.id = mu.user_id
                        left join asterisk_calls astk
                          on astk.caller_number = us.main_phone
                        left join datalake_clean.zendesk_user zu
                          on zu.email = us.email
                    )
                    select distinct
                        quintoandar_id,
                        email,
                        phone,
                        listagg("name", ',')
                        within group (order by "name")
                        over (partition by email, phone) as names,
                        listagg(asterisk_id, ',')
                        within group (order by asterisk_id)
                        over (partition by email, phone) as asterisk_ids,
                        listagg(zendesk_id, ',')
                        within group (order by zendesk_id)
                        over (partition by email, phone) as zendesk_ids,
                        listagg(amplitude_id, ',')
                        within group (order by amplitude_id)
                        over (partition by email, phone) as amplitude_ids
                    from all_info
                    """,
            db_enum=EnumDb.BI_DW,
        )

        return petl.todataframe(table)

    def get_data_from_elasticsearch(self, phone, email):
        result = self.es.search(index='user', params={'q': 'phone:{0}&email:{1}'.format(phone, email)})['hits']
        hits = result['hits']
        if len(hits) == 0:
            return

        for hit in hits:
            _logger.info(hit['_source'])

    def send_data_to_elasticsearch(self, df_user):
        df_user = df_user.astype(object).where(pd.notnull(df_user), None)

        actions = []
        for _, user_row in df_user.iterrows():
            user_phone = None
            if user_row['phone']:
                user_phone_regex = re.sub('\D', '', (user_row['phone']))
                user_phone = None if user_phone_regex == '' else str(int(user_phone_regex))

            actions.append({
                '_op_type': 'index',
                '_index': 'users',
                '_type': 'user',
                '_source': {
                    'quintoandar_id': str(int(user_row['quintoandar_id'])) if user_row['quintoandar_id'] else None,
                    'email': user_row['email'] if user_row['email'] and user_row['email'] != '' else None,
                    'names': list(
                        set(user_row['names'].split(','))
                    ) if user_row['names'] else None,
                    'phone': user_phone,
                    'zendesk_ids': list(
                        set(user_row['zendesk_ids'].split(','))
                    ) if user_row['zendesk_ids'] else None,
                    'asterisk_ids': list(
                        set(user_row['asterisk_ids'].split(','))
                    ) if user_row['asterisk_ids'] else None,
                    'amplitude_ids': list(
                        set(user_row['amplitude_ids'].split(','))
                    ) if user_row['amplitude_ids'] else None
                }
            })

        result = helpers.bulk(self.es, actions)
        _logger.error('m=send_data_to_elasticsearch, data_sent={}'.format(result[0]))

        if len(result[1]) > 0:
            _logger.error('m=send_data_to_elasticsearch, errors={}'.format(result[1]))


if __name__ == '__main__':
    help_center = HelpCenter()

    if args[1] == 'load_data':
        df = help_center.get_user_info()
        help_center.send_data_to_elasticsearch(df_user=df)
    else:
        _logger.info('m=__main__, msg=arg \'{}\' not recognized'.format(args[1]))
