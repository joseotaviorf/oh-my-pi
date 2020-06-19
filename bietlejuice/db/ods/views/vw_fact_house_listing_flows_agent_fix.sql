drop view if exists vw_fact_house_listing_flows_agent_fix;
create or replace view vw_fact_house_listing_flows_agent_fix as
with legacy_doorman as (
  select
    porteiros_legado."Status" as status,
    892700000 + porteiros_legado."Cod Imóvel"::double precision::bigint as imovel_id
  from gsheets.porteiros_legado
  where (porteiros_legado."Status" in ('Listing', 'Alugado', 'Foto', 'Foto com problema', 'Lead'))
    and porteiros_legado."Cod Imóvel" is not null
),
rn_lead as (
    select lead_tasks.rep_id,
        lead_tasks.lead_id,
        lead_tasks.dt_created,
        lead_tasks.dt_closed,
        row_number() over (partition by lead_tasks.lead_id order by lead_tasks.dt_created asc) as rn_first,
        row_number() over (partition by lead_tasks.lead_id order by lead_tasks.dt_created desc) as rn_last
    from crm.lead_tasks
    where date(dt_created) >= '2020-01-01'
),
-- first conversion task created for a lead
base_lead_tasks_first as (
    select
        rn_lead.rep_id,
        rn_lead.lead_id,
        rn_lead.dt_created,
        rn_lead.dt_closed
    from rn_lead
    where rn_first = 1
),
-- last conversion task created for a lead
base_lead_tasks_last as (
  select
      rn_lead.rep_id,
      rn_lead.lead_id,
      rn_lead.dt_created,
      rn_lead.dt_closed
  from rn_lead
  where rn_last = 1
),
base_photo_tasks as (
  select distinct
    coalesce(h.id, h_direct.id)::integer as house_id,
    max((task_type = 'AgendarJobDeFotografo')::integer)::boolean as has_job_photo,
    max((task_type = 'FupFoto')::integer)::boolean as has_fup_photo
  from crm.photo_tasks pt
  left join photo_job pj
    on pt.origin_id = pj.id
  left join house h
    on h.id = pj.imovel_id
  left join house h_direct
    on h_direct.id = pt.origin_id
  where coalesce(h.id, h_direct.id) is not null
  group by 1
),
base_leads as (
  select
    lead.id as lead_id,
    lead.tipo as lead_type,
    lead.origem as lead_origin,
    lead.utm_source,
    lead.utm_medium,
    coalesce(lower(btrim(lead.utm_campaign)) ~* '(institucional)|(branded)' and lower(btrim(lead.utm_campaign)) !~* '(non-branded)', false) as branded_lead,
    lead.codigo_imobiliaria is not null OR lead.flg_b2b as b2b_lead,
    case
      when lead.origem = 'Reprocessado'
        then ( select rl.id_origin_lead from reprocessed_lead rl where rl.id = lead.id)
      else NULL::bigint
    end as old_lead_id
  from lead
  where date(captado_em) >= '2020-01-01'
),
rep_leads as (
  select bl.lead_id,
    coalesce(old_bl.lead_type, bl.lead_type) as lead_type,
    coalesce(old_bl.lead_origin, bl.lead_origin) as lead_origin,
    coalesce(old_bl.utm_source, bl.utm_source) as utm_source,
    coalesce(old_bl.utm_medium, bl.utm_medium) as utm_medium,
    coalesce(old_bl.branded_lead, bl.branded_lead) as branded_lead,
    coalesce(old_bl.b2b_lead, bl.b2b_lead) as b2b_lead,
    coalesce(bl.lead_origin = 'Reprocessado', false) as reprocessed_flg
    from base_leads bl
    left join base_leads old_bl
      on old_bl.lead_id = bl.old_lead_id
),
acquisitions as (
  select
    f.id,
    case
      when d.imovel_id is not null and f.is_not_reprocessed then 'Lead Flow'
      else f.flow
    end as flow,
    case
      when d.imovel_id is not null and f.is_not_reprocessed then 'Non-Self Service'
      else f.acquisition_method
    end as acquisition_method,
    case
      when d.imovel_id is not null and f.is_not_reprocessed then 'Doorman'
      else f.acquisition_channel_rep
    end as acquisition_channel,
    case
      when d.imovel_id is not null and f.is_not_reprocessed then 'Doorman'
      else f.acquisition_source
    end as acquisition_source,
    case
      when d.imovel_id is not null and f.is_not_reprocessed then true
      else f.acquisition_source = 'Doorman'
    end as is_doorman
  from listing_flows_with_reprocessed_leads f
  left join legacy_doorman d
    on f.imovel_id = d.imovel_id
  where date(dt_lead) >= '2020-01-01'
),
leads_b2b as (
  select distinct
    l.id as id_lead,
    pa_b2b_online.partner_id as online_partner_id
  from lead l
  left join partner_agent pa_b2b_online
    on pa_b2b_online.user_id = l.usuario_que_indicou_id
  where pa_b2b_online.partner_id is not null
),
lead_city_region as (
  with city_region as (
    select
      region.id as id_region,
      regexp_replace(remove_accentuation(lower(region.nome)), '[^a-z]+', '', 'g') as formatted_city
    from region
    where region.nivel = 'Cidade'
  )
  select
    l.id,
    r.id_region
  from lead l
  join city_region r
    on r.formatted_city = regexp_replace(remove_accentuation(lower(l.cidade)), '[^a-z]+', '', 'g')
),
potential_listings as (
    select f.id as sk_house_listing_flow,
    coalesce(h.condo_id, '-1'::integer::bigint) as sk_condo,
    coalesce(f.lead_id, '-1'::integer) as sk_lead,
    coalesce(f.conversao_id, '-1'::integer) as sk_lead_conversion,
    coalesce(f.photo_job_id, '-1'::integer) as sk_first_photo_job,
    coalesce(f.imovel_id || '00' || coalesce(hl_version_zero.version, 1)::varchar, '-1')::bigint as sk_house_listing,
    coalesce(f.rep_id, '-1'::integer) as sk_user_house_registrant,
    coalesce(f.rep_id, btl.rep_id, '-1'::integer) as sk_user_sales_rep,
    coalesce(f.affiliate_id, f.origin_lead_usuario_que_indicou_id::integer, '-1'::integer) as sk_user_lead_affiliate,
    coalesce(btf.rep_id, '-1'::integer) as sk_user_first_task_assignee,
    coalesce(btl.rep_id, '-1'::integer) as sk_user_last_task_assignee,
    coalesce(f.region_id, '-1'::integer) as sk_region,
    coalesce(f.first_region_id, '-1'::integer) as sk_first_region,
    coalesce(dr.city_id, lcr.id_region, '-1'::integer) as sk_city,
    coalesce(pa_b2b_prime.partner_id, l_b2b.online_partner_id, f.partner_id, '-1'::integer::bigint) as sk_partner,
    coalesce(to_char(f.dt_lead::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_lead_date,
    coalesce(to_char(f.dt_prospect::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_prospect_date,
    coalesce(to_char(btf.dt_created::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_first_task_created_date,
    coalesce(to_char(btf.dt_closed::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_first_task_closed_date,
    coalesce(to_char(btl.dt_created::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_last_task_created_date,
    coalesce(to_char(btl.dt_closed::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_last_task_closed_date,
    coalesce(to_char(f.dt_first_contact::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_first_contact_date,
    coalesce(to_char(f.dt_conversion::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_conversion_date,
    coalesce(to_char(f.dt_qualified::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_qualified_date,
    coalesce(to_char(f.dt_opportunity::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_opportunity_date,
    coalesce(to_char(f.dt_first_listing::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_first_listing_date,
    coalesce(to_char(f.dt_discarded::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_discard_date,
    coalesce(to_char(f.ts_sales_company_sent, 'YYYYMMDD')::integer, '-1'::integer) as sk_sales_company_lead_sent_date,
    coalesce(f.user_id_lead_first_discarder, '-1'::integer) as sk_user_lead_first_discarder,
    coalesce(f.user_id_lead_last_discarder, '-1'::integer) as sk_user_lead_last_discarder,
    a.flow,
    a.acquisition_method,
    a.acquisition_channel,
    a.acquisition_source,
    case
      when f.dt_first_listing is not null then 'listing'
      when f.dt_opportunity is not null then 'opportunity'
      when f.dt_qualified is not null then 'qualified'
      when f.dt_prospect is not null then 'prospect'
      when f.dt_lead is not null then 'lead'
      else NULL
    end as funnel_step,
    f.funnel_step as funnel_drop_reason,
    f.hours_lead_to_prospect,
    f.hours_prospect_to_qualified,
    f.hours_lead_to_first_contact,
    f.hours_prospect_to_first_contact,
    f.hours_qualified_to_opportunity,
    f.hours_opportunity_to_listing,
    f.hours_lead_to_listing,
    f.days_lead_to_prospect,
    f.days_prospect_to_qualified,
    f.days_lead_to_first_contact,
    f.days_prospect_to_first_contact,
    f.days_qualified_to_opportunity,
    f.days_opportunity_to_listing,
    f.days_lead_to_listing,
    f.days_lead_to_processing,
    h.exclusivity as is_exclusive,
    case
      when btf.rep_id is not null then 'Lead'
      when coalesce(bpt.house_id, f.rep_id) is not null then 'Photojob'
      else null
    end as first_isales_intervention,
    bl.lead_type,
    bl.lead_origin,
    case when lfet.id_lead is not null then lfet.tracking_source else bl.utm_source end as utm_source,
    case when lfet.id_lead is not null then lfet.tracking_medium else bl.utm_medium end as utm_medium,
    lfet.tracking_platform,
    coalesce(lower(btrim(lfet.tracking_campaign)) ~* '(institucional)|(branded)' and lower(btrim(lfet.tracking_campaign)) !~* '(non-branded)',
             bl.branded_lead) as is_branded,
    f.is_b2b,
    bl.reprocessed_flg,
    a.is_doorman,
    f.acquisition_channel_rep = 'Inside Sales' as is_isales_direct_register,
    f.acquisition_channel_rep = 'Admin' as is_cx_direct_register,
    (f.acquisition_channel_rep = 'Inside Sales') or (f.acquisition_channel_rep = 'Admin') as is_ops_direct_register,
    coalesce(f.isales_registrant_id, btf.rep_id) is not null
    or (bpt.has_job_photo = true and not f.is_self_service_photo_job_scheduled)
        as has_isales_intervention,
    bpt.has_fup_photo as has_fup_photo_task,
    us_cad.id is not null as is_call_center,
    lfet.tracking_referring_domain as lead_referring_domain,
    case
    	when lower(lfet.tracking_referring_domain) LIKE '%corretor%' THEN 'Agents'
    	when lower(lfet.tracking_referring_domain) LIKE '%indicaai%' THEN 'Indica Ai'
    	when lower(lfet.tracking_referring_domain) LIKE '%proprietario%' THEN 'Owner'
    	else 'Other'
    end as lead_referring_category,
    us_d.subscriptionSource as subscription_source,
    coalesce(f.affiliate_type,
            case when ua.affiliateType = 'Doorman' and u.dados_agente_id is not null then 'Doorman & Agent'
            when u.dados_agente_id is not null then 'Agent'
            else ua.affiliateType
            end) as affiliate_type,
    f.is_agent_referral
  from listing_flows_with_reprocessed_leads f
  left join lead_first_event_tracking lfet
    on lfet.id_lead = f.lead_id
  left join acquisitions a
    on a.id = f.id
  left join base_lead_tasks_first btf
    on btf.lead_id = f.lead_id
  left join base_lead_tasks_last btl
    on btl.lead_id = f.lead_id
  left join base_photo_tasks bpt
    on f.imovel_id = bpt.house_id
  left join rep_leads bl
    on bl.lead_id = f.lead_id
  left join house h
    on f.imovel_id = h.id
  left join usuario us_cad
    on us_cad.id = h.usuario_que_cadastrou_id
      and us_cad.email ~~ '%@hargos.com.br'
  left join staging.dim_region dr
    on dr.sk_region = f.region_id
  left join lead_city_region lcr
    on coalesce(f.region_id, '-1'::integer) = '-1'::integer and f.lead_id = lcr.id
  left join leads_b2b l_b2b
    on l_b2b.id_lead = f.lead_id
  left join partner_agent pa_b2b_prime
    on h.usuario_id = pa_b2b_prime.user_id
  left join usuario u
	on coalesce(f.affiliate_id, f.origin_lead_usuario_que_indicou_id::integer, '-1'::integer) = u.id
  left join user_doorman us_d
    on us_d.id_dados_afiliado = u.dados_afiliado_id
  left join user_affiliate ua
    on ua.id = u.dados_afiliado_id
  left join house_listing hl_version_zero
  	on hl_version_zero.id_house = f.imovel_id
  	  and hl_version_zero.version = 0
),
taxonomy as (
  select
    distinct
    lead_type,
    lead_origin,
    lead_tracking_medium,
    lead_tracking_source,
    affiliate_type,
    lead_referring_category,
    is_agent_referral::integer::boolean as is_agent_referral,
    is_branded::integer::boolean as is_branded,
    is_ops_direct_register::integer::boolean as is_ops_direct_register,
    mkt_origin,
    mkt_channel,
    mkt_medium,
    mkt_source
  from
    gsheets.taxonomy_growth_agent_fix
  where
    coalesce(mkt_medium, '') <> 'Doorman User'
    and mkt_origin <> 'B2B'
),
applied_taxonomy as (
select
  pl.*,
  case
    when pl.is_branded then 'Branded'
    else 'Other'
  end as mkt_branded,
  case
    when pl.is_b2b then 'B2B'
    when pl.affiliate_type = 'Doorman' then 'Doorman'
    when t.mkt_origin is null then 'Other'
    else t.mkt_origin
  end as mkt_origin,
  case
    when pl.is_b2b then null
    when pl.affiliate_type = 'Doorman' then 'Envio'
    when t.mkt_origin is null then 'Not Mapped'
    else t.mkt_channel
  end as mkt_channel,
  case
    when t.mkt_origin is null then 'Not Mapped'
    when pl.tracking_platform = 'web_mobile' then 'Web Mobile'
    when pl.tracking_platform = 'web_desktop' then 'Web Desktop'
    else 'Not Mapped'
  end as mkt_platform,
  case
    when pl.is_b2b then null
    when pl.affiliate_type = 'Doorman' then 'Doorman User'
    when t.mkt_origin is null then 'Not Mapped'
    else t.mkt_medium
  end as mkt_medium,
  case
    when pl.is_b2b then null
    when pl.affiliate_type = 'Doorman' then (
        case
            when COALESCE(pl.subscription_source, '') in ('', 'Desconhecida')   then 'Cadastro Orgânico'
            when pl.subscription_source = 'LeadOutbound'                        then 'Captação Call Center'
            when pl.subscription_source = 'Trade'                               then 'Captação Offline'
            else t.mkt_source
        end
    )
    when t.mkt_origin is null then 'Not Mapped'
    else t.mkt_source
  end as mkt_source,
  now() as ts_load
from potential_listings pl
left join taxonomy t
  on coalesce(pl.lead_type, '') = coalesce(t.lead_type, '')
    and coalesce(pl.lead_origin, '') = coalesce(t.lead_origin, '')
    and coalesce(pl.utm_source, '') = coalesce(t.lead_tracking_source, '')
    and coalesce(pl.utm_medium, '') = coalesce(t.lead_tracking_medium, '')
    and coalesce(pl.affiliate_type, '') = coalesce(t.affiliate_type, '')
    and coalesce(pl.lead_referring_category, '') = coalesce(t.lead_referring_category, '')
    and coalesce(pl.is_branded, false) = coalesce(t.is_branded, false)
    and coalesce(pl.is_ops_direct_register, false) = coalesce(t.is_ops_direct_register, false)
    and coalesce(pl.is_agent_referral, false) = coalesce(t.is_agent_referral, false)
),
applied_taxonomy_flow as (
    select
        *,
        case
             when lead_type = 'Proparceria'                                                 then 'Non Self-Service'
             when lead_type = 'Marketing' and lead_origin in ('Facebook', 'Reprocessado')   then 'Non Self-Service'
             when is_ops_direct_register                                                        then 'Non Self-Service'
             when lead_origin = 'Landing'                                                   then 'Non Self-Service'
             when mkt_origin in ('Owner PWA', 'Price Calculator')                           then 'Self-Service'
             when mkt_origin in ('Indica Aí - Agents', 'Indica Aí - General')
                  and mkt_source = 'Direct Referral'                                        then 'Self-Service'
             when mkt_origin in ('Other', 'Not Mapped')                                     then mkt_origin
             else 'Non Self-Service'
        end as mkt_flow
    from  applied_taxonomy
)
select
  atax.sk_house_listing_flow,
  atax.sk_condo,
  atax.sk_lead,
  atax.sk_lead_conversion,
  atax.sk_first_photo_job,
  atax.sk_house_listing,
  atax.sk_user_house_registrant,
  atax.sk_user_sales_rep,
  atax.sk_user_lead_affiliate,
  atax.sk_user_first_task_assignee,
  atax.sk_user_last_task_assignee,
  atax.sk_region,
  atax.sk_first_region,
  atax.sk_city,
  atax.sk_partner,
  atax.sk_lead_date,
  atax.sk_sales_company_lead_sent_date,
  atax.sk_prospect_date,
  atax.sk_first_task_created_date,
  atax.sk_first_task_closed_date,
  atax.sk_last_task_created_date,
  atax.sk_last_task_closed_date,
  atax.sk_first_contact_date,
  atax.sk_conversion_date,
  atax.sk_qualified_date,
  atax.sk_opportunity_date,
  atax.sk_first_listing_date,
  atax.sk_discard_date,
  atax.sk_user_lead_first_discarder,
  atax.sk_user_lead_last_discarder,
  atax.funnel_step,
  atax.funnel_drop_reason,
  atax.hours_lead_to_prospect,
  atax.hours_prospect_to_qualified,
  atax.hours_lead_to_first_contact,
  atax.hours_prospect_to_first_contact,
  atax.hours_qualified_to_opportunity,
  atax.hours_opportunity_to_listing,
  atax.hours_lead_to_listing,
  atax.days_lead_to_prospect,
  atax.days_prospect_to_qualified,
  atax.days_lead_to_first_contact,
  atax.days_prospect_to_first_contact,
  atax.days_qualified_to_opportunity,
  atax.days_opportunity_to_listing,
  atax.days_lead_to_listing,
  atax.days_lead_to_processing,
  atax.is_exclusive,
  atax.first_isales_intervention,
  atax.lead_type,
  atax.lead_origin,
  atax.utm_source as lead_tracking_source,
  atax.utm_medium as lead_tracking_medium,
  atax.tracking_platform as lead_tracking_platform,
  atax.is_branded,
  atax.is_b2b,
  atax.is_doorman,
  atax.is_isales_direct_register,
  atax.is_cx_direct_register,
  atax.is_ops_direct_register,
  atax.has_isales_intervention,
  atax.has_fup_photo_task,
  atax.is_call_center,
  atax.reprocessed_flg as is_lead_reprocessed,
  atax.affiliate_type,
  atax.is_agent_referral,
  atax.lead_referring_domain,
  atax.lead_referring_category,
  atax.subscription_source,
  atax.mkt_branded,
  case when atax.mkt_flow = 'Self-Service' then 'Outbound'
       when atax.mkt_flow = 'Non Self-Service' and atax.lead_origin in ('App', 'Crawling', 'Form', 'Planilha') then 'Outbound'
       when atax.mkt_flow = 'Non Self-Service' and atax.lead_origin in ('Facebook', 'Landing', 'OwnerPWA', 'Price Suggestion') then 'Inbound'
       when atax.mkt_flow = 'Not Mapped' then 'Not Mapped'
       else 'Other' end as mkt_category,
  atax.mkt_flow,
  case when atax.mkt_flow = 'Non Self-Service' then 'Non Self-Service'
       when atax.mkt_flow = 'Self-Service' and not atax.has_isales_intervention then 'Full Self-Service'
       when atax.mkt_flow = 'Self-Service' and atax.has_isales_intervention then 'Recovered Self-Service'
       when atax.mkt_flow in ('Not Mapped', 'Other') then atax.mkt_flow
       else 'Not Mapped' end as mkt_completion,
  atax.mkt_origin,
  atax.mkt_channel,
  atax.mkt_platform,
  atax.mkt_medium,
  atax.mkt_source,
  atax.ts_load
from applied_taxonomy_flow atax
