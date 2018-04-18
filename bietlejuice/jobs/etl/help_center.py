# encoding: utf-8
import sys

reload(sys)
sys.setdefaultencoding('utf8')

import json
import os
import re
import sys
from collections import OrderedDict

import pandas as pd
import petl
from elasticsearch import Elasticsearch
from elasticsearch import helpers

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDb
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
                        trim(split_part(cp.email, ',', ns.n)) as email, cp.telefone, cp.nome, cp.tipo, cp.contrato_id
                      from ns
                        join datalake_clean.ebdb_contract_person cp
                          on ns.n <= regexp_count(trim(cp.email), ',') + 1
                    ),
                    ns_p as (
                      select
                        trim(split_part(cp.email, ';', ns.n)) as email, cp.telefone, cp.nome, cp.tipo, cp.contrato_id
                      from ns
                        join datalake_clean.ebdb_contract_person cp
                          on ns.n <= regexp_count(trim(cp.email), ';') + 1
                    ),
                    union_all as (
                      select email, telefone, nome, tipo, contrato_id
                      from ns_c
                        union all
                      select email, telefone, nome, tipo, contrato_id
                      from ns_p
                    ),
                    contrato_pessoa as (
                      select distinct trim(email) as email, telefone, nome, tipo, contrato_id
                      from union_all
                        where email is not null
                        and trim(email) != ''
                    ),
                    users_prev as (
                      select distinct
                        coalesce(uc.email, up.email, cp.email, pp.email) as email,
                        coalesce(uc.telefoneprincipal, up.telefoneprincipal) as main_phone,
                        coalesce(uc.telefonesecundario, up.telefonesecundario) as secondary_phone,
                        coalesce(uc.telefoneComercial, up.telefoneComercial) as commercial_phone,
                        cp.telefone as contract_phone,
                        pp.telefone as proposal_phone,
                        pp.tipo as pp_type,
                        cp.tipo as cp_type,
                        ec.id as ec_id,
                        coalesce(uc.nome, up.nome, cp.nome) as name,
                        coalesce(uc.id, up.id, null) as id,
                        coalesce(uc.tipoadmin, up.tipoadmin) as tipoadmin,
                        coalesce(uc.bloqueado, up.bloqueado) as bloqueado,
                        coalesce(uc.dadosagente_id, up.dadosagente_id) as dadosagente_id,
                        coalesce(uc.dadosfotografo_id, up.dadosfotografo_id) as dadosfotografo_id,
                        coalesce(uc.dadosafiliado_id, up.dadosafiliado_id) as dadosafiliado_id,
                        coalesce(uc.dadosvendedor_id, up.dadosvendedor_id) as dadosvendedor_id
                      from contrato_pessoa cp
                        left join datalake_clean.ebdb_contract ec
                            on cp.contrato_id = ec.id
                                and ec.status in ('Finalizado', 'Ativo')
                        full outer join datalake_clean.ebdb_proponent_proposal pp
                          on pp.email = cp.email
                        full outer join datalake_clean.ebdb_user up
                          on up.email = pp.email
                        full outer join datalake_clean.ebdb_user uc
                          on uc.email = cp.email
                    ),
                    users as (
                      select distinct
                        up.email,
                        main_phone,
                        secondary_phone,
                        commercial_phone,
                        contract_phone,
                        proposal_phone,
                        up.name,
                        up.id,
                        (
                         '' || 
                            case
                              when p.id is not null and trim(p.id) != ''
                                then ',landlord'
                              else ''
                            end
                            || 
                            case
                              when ec_id is not null and trim(ec_id) != '' and trim(pp_type) = 'Inquilino'
                                then ',tenant_with_contract'
                              else ''
                            end
                            ||
                            case
                              when eb.id is not null and trim(eb.id) != ''
                                then ',tenant_with_visit'
                              else ''
                            end
                            ||
                            case
                              when trim(pp_type) = 'Inquilino'
                                then ',tenant_with_negotiation'
                              else ''
                            end
                            ||
                            case
                              when up.cp_type = 'Proprietario'
                                then ',landlord_in_contract'
                              when up.cp_type = 'Inquilino'
                                then ',tenant_in_contract'
                              else ''
                            end
                            ||
                            case
                              when trim(up.tipoadmin) in ('Admin','Sudo','Contratos','Financeiro','AtendimentoParceiros')
                                and trim(up.bloqueado) = 'false' 
                                then ',admin'
                              else ''
                            end
                            ||
                            case
                              when pd.id is not null and trim(pd.id) != ''
                                then ',agent_photographer'
                              else ''
                            end
                            ||
                            case
                              when ad.id is not null and trim(ad.id) != '' 
                                then ',affiliate'
                              else ''
                            end
                            ||
                            case
                              when sd.id is not null and trim(sd.id) != ''
                                then ',seller'
                              else ''
                            end
                            ||
                            case
                              when up.dadosagente_id is not null and trim(up.dadosagente_id) != ''
                                then ',agent_agent'
                              else ''
                            end
                            ||
                            case
                              when up.dadosagente_id is not null and trim(up.dadosagente_id) != '' and trim(dat.tipos) = 'Vistoria'
                                then ',agent_inspector'
                              else ''
                            end
                            ||
                         ''
                        ) as roles
                      from users_prev up
                      left join datalake_clean.ebdb_property p 
                        on p.usuario_id = up.id
                            and p.status != 'excluido'
                      left join datalake_clean.ebdb_photographer_data pd 
                        on pd.id = up.dadosfotografo_id
                          and pd.ativo = 'true'
                      left join datalake_clean.ebdb_affiliate_data ad 
                        on ad.id = up.dadosafiliado_id
                          and ad.ativo = 'true'
                      left join datalake_clean.ebdb_seller_data sd 
                        on sd.id = up.dadosvendedor_id 
                          and sd.ativo = 'true'
                      left join datalake_clean.ebdb_agent_data_type dat
                        on dat.dadosagente_id = up.dadosagente_id
                      left join datalake_clean.ebdb_booking eb
                        on eb.visitante_id = up.id
                          and eb.tipo = 'Visita'
                    ),
                    all_info as (
                      select distinct
                        us.id as quintoandar_id,
                        trim(us.email) as email,
                        trim(us.name) as "name",
                        us.roles as roles,
                        coalesce(us.main_phone, '') 
                         || ',' || coalesce(us.secondary_phone, '') 
                         || ',' || coalesce(us.commercial_phone, '') 
                         || ',' || coalesce(us.contract_phone, '') 
                         || ',' || coalesce(us.proposal_phone, '')
                        as phones,
                        mu.amplitude_id as amplitude_id,
                        zu.id as zendesk_id
                      from users us
                      left join amplitude_events.merged_users mu
                        on us.id = mu.user_id
                      left join datalake_clean.zendesk_user zu
                        on zu.email = us.email
                    )
                    select distinct
                        quintoandar_id,
                        email,
                        roles,
                        phones,
                        listagg("name", ',')
                        within group (order by "name")
                        over (partition by quintoandar_id, email) as names,
                        listagg(zendesk_id, ',')
                        within group (order by zendesk_id)
                        over (partition by quintoandar_id, email) as zendesk_ids,
                        listagg(amplitude_id, ',')
                        within group (order by amplitude_id)
                        over (partition by quintoandar_id, email) as amplitude_ids
                    from all_info
            """,
            db_enum=EnumDb.BI_DW,
        )

        return petl.todataframe(table)

    @logger
    def get_data_from_elasticsearch(self, phone, email):
        result = self.es.search(index='users', params={'q': 'phone:{0}&email:{1}'.format(phone, email)})['hits']
        hits = result['hits']
        if len(hits) == 0:
            return

        for hit in hits:
            _logger.info(hit['_source'])

    @logger
    def clean_elasticsearch(self):
        success = False
        while not success:
            try:
                response = self.es.delete_by_query(index='hc-users', body={'query': {'match_all': dict()}})
                success = not response['timed_out'] and len(response['failures']) == 0
            except Exception as e:
                _logger.error('m=clean_elasticsearch, message_error={}'.format(e.message))

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
                    'email': self.__split_and_filter(user_row['email']),
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
        _logger.error('m=send_data_to_elasticsearch, data_sent={}'.format(result[0]))

        if len(result[1]) > 0:
            _logger.error('m=send_data_to_elasticsearch, errors={}'.format(result[1]))

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


if __name__ == '__main__':
    help_center = HelpCenter()

    if args[1] == 'load_data':
        df = help_center.get_user_info()
        help_center.clean_elasticsearch()
        help_center.send_data_to_elasticsearch(df_user=df)
    else:
        _logger.info('m=__main__, msg=arg \'{}\' not recognized'.format(args[1]))
