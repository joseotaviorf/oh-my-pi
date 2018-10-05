# -*- coding: latin-1 -*-

import json
from datetime import datetime

import requests
from pytz import UTC, timezone
from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.dags.util import environment as env

env.set_airflow_var_to_local_env('EBDB')
endpoint = env.get_airflow_env_var('LEADS_ENDPOINT')

logger = QuintoAndarLogger('bi-dashboard-growth-leads')


def fix_timezone(dt):
    if isinstance(dt, datetime):
        return dt.replace(tzinfo=UTC).astimezone(timezone('America/Sao_Paulo'))
    else:
        return None


def datetime_converter(dt):
    if isinstance(dt, datetime):
        return dt.strftime('%Y-%m-%d %H:%M:%S')
    else:
        return None


def __get_leads():
    table = BaseETL.from_db_query(
        db_enum=EnumDB.QuintoAndar_ebdb,
        query='''
            select
                sum(case when city = 'rj' and date(tbl.dt_lead) = current_date then 1 else 0 end) as rj_leads,
                sum(case when city = 'rj' and date(tbl.dt_prospect) = current_date then 1 else 0 end) as rj_prospects,
                sum(case when city = 'rj' and date(tbl.dt_qualified) = current_date then 1 else 0 end) as rj_qualifieds,
                sum(case when city = 'rj' and date(tbl.dt_opportunity) = current_date then 1 else 0 end) as rj_opportunities,
                sum(case when city = 'rj' and date(tbl.dt_first_listing) = current_date then 1 else 0 end) as rj_listings,
                sum(case when city = 'bsb' and date(tbl.dt_lead) = current_date then 1 else 0 end) as bsb_leads,
                sum(case when city = 'bsb' and date(tbl.dt_prospect) = current_date then 1 else 0 end) as bsb_prospects,
                sum(case when city = 'bsb' and date(tbl.dt_qualified) = current_date then 1 else 0 end) as bsb_qualifieds,
                sum(case when city = 'bsb' and date(tbl.dt_opportunity) = current_date then 1 else 0 end) as bsb_opportunities,
                sum(case when city = 'bsb' and date(tbl.dt_first_listing) = current_date then 1 else 0 end) as bsb_listings,
                sum(case when city = 'go' and date(tbl.dt_lead) = current_date then 1 else 0 end) as go_leads,
                sum(case when city = 'go' and date(tbl.dt_prospect) = current_date then 1 else 0 end) as go_prospects,
                sum(case when city = 'go' and date(tbl.dt_qualified) = current_date then 1 else 0 end) as go_qualifieds,
                sum(case when city = 'go' and date(tbl.dt_opportunity) = current_date then 1 else 0 end) as go_opportunities,
                sum(case when city = 'go' and date(tbl.dt_first_listing) = current_date then 1 else 0 end) as go_listings,
                sum(case when city = 'bh' and date(tbl.dt_lead) = current_date then 1 else 0 end) as bh_leads,
                sum(case when city = 'bh' and date(tbl.dt_prospect) = current_date then 1 else 0 end) as bh_prospects,
                sum(case when city = 'bh' and date(tbl.dt_qualified) = current_date then 1 else 0 end) as bh_qualifieds,
                sum(case when city = 'bh' and date(tbl.dt_opportunity) = current_date then 1 else 0 end) as bh_opportunities,
                sum(case when city = 'bh' and date(tbl.dt_first_listing) = current_date then 1 else 0 end) as bh_listings,
                sum(case when city = 'sp' and date(tbl.dt_lead) = current_date then 1 else 0 end) as sp_leads,
                sum(case when city = 'sp' and date(tbl.dt_prospect) = current_date then 1 else 0 end) as sp_prospects,
                sum(case when city = 'sp' and date(tbl.dt_qualified) = current_date then 1 else 0 end) as sp_qualifieds,
                sum(case when city = 'sp' and date(tbl.dt_opportunity) = current_date then 1 else 0 end) as sp_opportunities,
                sum(case when city = 'sp' and date(tbl.dt_first_listing) = current_date then 1 else 0 end) as sp_listings
            from
            (
                select
                    case
                        when coalesce(i.cidade, l.cidade) in ('Belo Horizonte', 'Nova Lima') then 'bh'
                        when coalesce(i.cidade, l.cidade) in ('Brasília') then 'bsb'
                        when coalesce(i.cidade, l.cidade) in ('Goiânia') then 'go'
                        when coalesce(i.cidade, l.cidade) in ('Rio de Janeiro') then 'rj'
                        else 'sp'
                    end as city,
                    base.lead_id,
                    base.conversao_id,
                    jf2.id as photo_job_id,
                    base.imovel_id,
                    base.rep_id,
                    base.affiliate_id,
                    base.owner_id,
                    base.region_id,
                    photographer.id as photographer_id,
                    base.dt_lead,
                    base.dt_prospect,
                    case
                        when (base.lead_status = 'Descartado' and coalesce(jf.dataCriacao, jf.dataAgendamento, jf.dataAceitoFotografo, jf.dataUploadFotos) is null)
                            then null
                        else base.dt_qualified
                    end as dt_qualified,
                    coalesce(jf.dataCriacao, jf.dataAgendamento, jf.dataAceitoFotografo, jf.dataUploadFotos) as dt_opportunity,
                    i.firstPublication as dt_first_listing,
                    base.flow,
                    base.acquisition_method,
                    base.acquisition_channel
                from
                (
                    select
                        i.id as imovel_id,
                        null as lead_id,
                        null as lead_status,
                        null as conversao_id,
                        case
                            when (i.usuarioQueCadastrou_id=i.usuario_id and u.tipoAdmin = 'Normal' and u.email not like '%quintoandar%')
                            then NULL
                            else i.usuarioQueCadastrou_id
                        end as rep_id,
                        null as affiliate_id,
                        i.usuario_id as owner_id,
                        i.regiao_id as region_id,
                        i.dataCriacao as dt_lead,
                        i.dataCriacao as dt_prospect,
                        from_unixtime(ure.timestamp/1000) as dt_qualified,
                        case
                            when (i.usuarioQueCadastrou_id=i.usuario_id and u.tipoAdmin = 'Normal' and u.email not like '%quintoandar%')
                            then 'Self Service Flow'
                            else 'Organic Flow'
                        end as flow,
                        case
                            when (i.usuarioQueCadastrou_id=i.usuario_id and u.tipoAdmin = 'Normal' and u.email not like '%quintoandar%')
                            then 'Self-Service'
                            else 'Non-Self Service'
                        end as acquisition_method,
                        case
                            when (i.usuarioQueCadastrou_id=i.usuario_id and u.tipoAdmin = 'Normal' and u.email not like '%quintoandar%')
                            then 'Owner App'
                            else 'Admin'
                        end as acquisition_channel
                    from
                        Imovel i
                    left join
                        ConversaoLead cl
                        on cl.imovel_id = i.id
                    left join
                        Usuario u
                        on u.id = i.usuarioQueCadastrou_id
                    left join
                        (
                            select
                          min(REV) as REV,
                          garantias,
                          Imovel_id
                        from
                            Imovel_garantias_AUD
                        where garantias in ('SeguroFiancaCardiff','SeguroFairfax')
                        group by Imovel_id
                      ) ig
                      on i.id = ig.Imovel_id
                      and ig.garantias in ('SeguroFiancaCardiff','SeguroFairfax')
                    left join
                      UsuarioRevisionEntity ure
                      on ig.REV = ure.id
                    where cl.id is null
                union all
                    select
                        i.id as imovel_id,
                        l.id as lead_id,
                        l.status as lead_status,
                        cl.id as conversao_id,
                        i.usuarioQueCadastrou_id as rep_id,
                        uda.id as affiliate_id,
                        i.usuario_id as owner_id,
                        i.regiao_id as region_id,
                        coalesce(l.criadoEm, l.anuncioCriadoEm, l.captadoEm) as dt_lead,
                        case
                            when has_aud.id is not null then from_unixtime(ure.timestamp/1000)
                            else coalesce(l.atualizadoEm, l.criadoEm) -- if there is no AUD records, we assume lead update or creation
                        end as dt_prospect,
                        case -- when excluded by specific reasons we count the lead as a qualified lead, even if its discarded
                        when cl.leadConvertido_id is not null
                            then coalesce(cl.dataConversao, cl.criadoEm, from_unixtime(ure.timestamp/1000))
                        when l.reason in ('ProprietarioRecusou', 'Exclusivo')
                            then coalesce(from_unixtime(dure.timestamp/1000), from_unixtime(ure.timestamp/1000))
                      end as qualified_date,
                        'Lead Flow' as flow,
                        'Non-Self Service' as acquisition_method,
                        case
                            when uda.id = 279289 then 'Doorman'
                        when l.tipo = 'Afiliado' and l.origem = 'App' then 'Affiliate App'
                        when l.tipo = 'Afiliado' and l.origem = 'Form' then 'Affiliate Form'
                        when l.tipo = 'Afiliado' and l.origem = 'Planilha' then 'Affiliate Spreadsheet'
                        when l.tipo = 'Afiliado' and l.origem = 'Desconhecida' then 'Affiliate Unknown'
                        when l.tipo = 'OpenLink' and l.origem = 'Landing' then 'Direct Referral'
                        when l.origem = 'Facebook' then 'Facebook'
                        when l.origem = 'Landing' then 'Landing Page Leads' -- BrokenOpenLink goes here also
                        when l.origem = 'Crawling' then 'Crawling'
                        when l.origem = 'Reprocessado' and old_lead.origem = 'Landing' then 'Reprocessed Landing'
                        when l.origem = 'Reprocessado' and old_lead.tipo = 'Afiliado' then 'Reprocessed Affiliate'
                        when l.origem = 'Reprocessado' then 'Reprocessed Others'
                        else 'Other'
                      end as acquisition_channel
                    from
                        (
                            select
                                *,
                                case
                                    when SUBSTRING_INDEX(infosExtras,';',1) REGEXP '^-?[0-9]+$'
                                        then SUBSTRING_INDEX(infosExtras,';',1)
                                    else NULL
                                end as old_id
                            from Lead
                        ) l -- all data from Lead table plus a reprocessed Extra Field
                    left join
                        ConversaoLead cl
                        on cl.leadConvertido_id = l.id
                    left join
                        Imovel i
                        on i.id = cl.imovel_id
                    left join
                        (
                            select
                                a.id,
                              min(a.REV) as REV
                            from
                              Lead_AUD a
                            where ((a.processado = 1 and a.processado_MOD = 1) or (a.status_MOD = 1 and a.status != 'Novo'))
                              and coalesce(a.automaticallyDiscarded, 0) = 0
                            group by a.id
                        ) first_update
                        on first_update.id = l.id
                    left join
                      Lead_AUD la
                      on la.id = l.id
                      and la.REV = first_update.REV
                    left join
                      UsuarioRevisionEntity ure
                      on ure.id = la.REV
                    left join
                        (select max(REV) as REV, id from Lead_AUD where status_MOD = 1 and status = 'Descartado' group by id) discard
                        on l.id = discard.id
                    left join
                      UsuarioRevisionEntity dure
                      on dure.id = discard.REV
                    left join
                        (select max(REV) as REV, id from Lead_AUD group by id) has_aud
                        on has_aud.id = l.id
                    left join
                      DadosAfiliado da
                      on da.id = l.afiliadoQueIndicou_id
                    left join
                      Usuario uda
                      on uda.dadosAfiliado_id = da.id
                    left join
                        Lead old_lead
                        on old_lead.id = l.old_id
                union all
                    select
                        i.id as imovel_id,
                        null as lead_id,
                        null as lead_status,
                        cl.id as conversao_id,
                        i.usuarioQueCadastrou_id as rep_id,
                        null as affiliate_id,
                        i.usuario_id as owner_id,
                        i.regiao_id as region_id,
                        i.dataCriacao as dt_lead,
                        i.dataCriacao as dt_prospect,
                        from_unixtime(ure.timestamp/1000) as dt_qualified,
                        'Organic Flow' as flow,
                        'Non-Self Service' as acquisition_method,
                        'Inside Sales' as acquisition_channel
                    from
                        ConversaoLead cl
                    left join
                        Imovel i
                        on i.id = cl.imovel_id
                    left join
                        Usuario u
                        on u.id = i.usuarioQueCadastrou_id
                    left join
                        (
                            select
                          min(REV) as REV,
                          garantias,
                          Imovel_id
                        from
                            Imovel_garantias_AUD
                        where garantias in ('SeguroFiancaCardiff','SeguroFairfax')
                        group by Imovel_id
                      ) ig
                      on i.id = ig.Imovel_id
                      and ig.garantias in ('SeguroFiancaCardiff','SeguroFairfax')
                    left join
                      UsuarioRevisionEntity ure
                      on ig.REV = ure.id
                    where leadConvertido_id is null
                ) base
                left join
                    (select imovel_id, min(id) as id from JobFotografo group by imovel_id) first_job
                    on base.imovel_id = first_job.imovel_id
                left join
                    JobFotografo jf
                    on jf.id = first_job.id
                left join
                    (select imovel_id, min(id) as id from JobFotografo where status = 'Publicado' group by imovel_id) photo_pub
                    on base.imovel_id = photo_pub.imovel_id
                left join
                    JobFotografo jf2
                    on jf2.id = photo_pub.id
                left join
                    Usuario photographer
                    on photographer.dadosFotografo_id = jf2.dadosFotografo_id
                left join
                    Imovel i
                    on i.id = base.imovel_id
                left join
                    Lead l
                    on l.id = base.lead_id
            ) tbl
            where
            (
                date(dt_lead) = current_date or
                date(dt_prospect) = current_date or
                date(dt_opportunity) = current_date or
                date(dt_first_listing) = current_date
            )
            ''')
    return table


def push_leads(endpoint):
    logger.info('get_leads')
    leads = __get_leads()
    header = list(leads[0])
    values = list(leads[1])

    output = {}
    for i in range(len(header)):
        print header[i], values[i], int(values[i])
        output[header[i]] = int(values[i])

    print output

    resp = requests.post(endpoint, json.dumps(output), timeout=30)
    logger.info('push_leads {}'.format(resp.content))


# create DAG definition
dag = BaseDAG.build_dag(
    dag_id='bi-dashboard-growth-leads',
    description='Feeder to PowerBI Real time lead dashboard',
    start_date=datetime(2018, 4, 12, 14, 15, 0),
    schedule_interval=env.convert_to_utc_schedule('0/5 * * * *')
)

contacts_and_prospects = BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='push_potential_listing_data',
    python_callable=push_leads,
    op_kwargs={'endpoint': endpoint}
)
