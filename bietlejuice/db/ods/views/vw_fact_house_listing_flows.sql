drop view if exists vw_fact_house_listing_flows;
create or replace view vw_fact_house_listing_flows as
with legacy_doorman as (
  select 
    porteiros_legado."Status" as status,
    892700000 + porteiros_legado."Cod Imóvel"::double precision::bigint as imovel_id
  from files.porteiros_legado
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
    coalesce(i.id, i_direct.id)::integer as imovel_id
  from crm.photo_tasks pt
  left join photo_job pj 
    on pt.origin_id = pj.id
  left join imovel i 
    on i.id = pj.imovel_id
  left join imovel i_direct 
    on i_direct.id = pt.origin_id
  where coalesce(i.id, i_direct.id) is not null
), 
base_leads as (
  select 
    lead.id as lead_id,
    lead.tipo as lead_type,
    lead.origem as lead_origin,
    lead.utm_source,
    lead.utm_medium,
    coalesce(lower(btrim(lead.utm_campaign)) ~* '(institucional)|(branded)', false) as branded_lead,
    lead.codigo_imobiliaria is not null OR lead.flg_b2b as b2b_lead,
    case
      when lead.origem = 'Reprocessado' 
        then ( select rl.id_origin_lead from reprocessed_lead rl where rl.id = lead.id)
      else NULL::bigint
    end as old_lead_id
  from lead
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
fact_with_reproc as (
  with reproc_leads as (
    select 
      rl.id,
      l.origem,
      l.tipo,
      l.usuario_que_indicou_id,
      l.affiliate_type
    from reprocessed_lead rl
    join lead l 
      on l.id = rl.id_origin_lead
  ),
  house_b2b_portability as (
    select
        hl.id_house_listing
    from house_listing hl
    join house h
        on h.id = hl.id_house
    join portability por
        on por.id_house = hl.id_house and por.owner_type = 'B2B'
    where hl.version = 0 and por.ts_created >= h.data_criacao
  ),
  acquisition_channels as (
    select 
      fhlf.id,
      fhlf.lead_id,
      fhlf.conversao_id,
      fhlf.photo_job_id,
      fhlf.imovel_id,
      fhlf.rep_id,
      fhlf.affiliate_id,
      fhlf.region_id,
      fhlf.first_region_id,
      fhlf.dt_lead,
      fhlf.dt_prospect,
      fhlf.dt_first_inside_sales_contact,
      fhlf.dt_conversion,
      fhlf.dt_qualified,
      fhlf.dt_opportunity,
      fhlf.dt_first_listing,
      fhlf.dt_discarded,
      fhlf.user_id_lead_first_discarder,
      fhlf.user_id_lead_last_discarder,
      fhlf.flow,
      fhlf.acquisition_method,
      fhlf.acquisition_channel,
      fhlf.acquisition_source,
      fhlf.funnel_step,
      fhlf.hours_lead_to_prospect,
      fhlf.hours_prospect_to_qualified,
      fhlf.hours_lead_to_first_inside_sales_contact,
      fhlf.hours_prospect_to_first_inside_sales_contact,
      fhlf.hours_qualified_to_opportunity,
      fhlf.hours_opportunity_to_listing,
      fhlf.hours_lead_to_listing,
      fhlf.days_lead_to_prospect,
      fhlf.days_prospect_to_qualified,
      fhlf.days_lead_to_first_inside_sales_contact,
      fhlf.days_prospect_to_first_inside_sales_contact,
      fhlf.days_qualified_to_opportunity,
      fhlf.days_opportunity_to_listing,
      fhlf.days_lead_to_listing,
      fhlf.days_lead_to_processing,
      case
        when l.origem = 'Reprocessado' and rl.origem = 'Landing' then 'Reprocessed Landing'
        when l.origem = 'Reprocessado' and rl.tipo = 'Afiliado' then 'Reprocessed Affiliate'
        when l.origem = 'Reprocessado' then 'Reprocessed Others'
        else fhlf.acquisition_channel
      end as acquisition_channel_rep,
      rl.usuario_que_indicou_id as origin_lead_usuario_que_indicou_id,
      coalesce(
            port.id is not null
            or coalesce(rl.affiliate_type, l.affiliate_type) = 'B2BPartner'
            or pa_b2b.id is not null
            or b2b_prime.id_lead is not null
            , false) as is_b2b
    from fact_house_listing_flows fhlf
    left join lead l 
      on l.id = fhlf.lead_id
    left join reproc_leads rl 
      on rl.id = fhlf.lead_id
    left join house h
      on h.id = fhlf.imovel_id
    left join partner_agent pa_b2b
      on pa_b2b.user_id = h.usuario_id
    left join (
		select distinct le.id as id_lead
		from lead le
		join usuario u_b2b
			on u_b2b.telefone_principal = le.telefone_anunciante
		join partner_agent pa_b2b
			on pa_b2b.user_id = u_b2b.id
	) b2b_prime
	  on b2b_prime.id_lead = l.id
	left join house_listing hl
        on hl.id_house = fhlf.imovel_id
        and hl.version = 0
    left join portability port
        on port.id_house = hl.id_house
        and port.owner_type = 'B2B'
  )
  select 
    acquisition_channels.id,
    acquisition_channels.lead_id,
    acquisition_channels.conversao_id,
    acquisition_channels.photo_job_id,
    acquisition_channels.imovel_id,
    acquisition_channels.rep_id,
    acquisition_channels.affiliate_id,
    acquisition_channels.region_id,
    acquisition_channels.first_region_id,
    acquisition_channels.dt_lead,
    acquisition_channels.dt_prospect,
    acquisition_channels.dt_first_inside_sales_contact,
    acquisition_channels.dt_conversion,
    acquisition_channels.dt_qualified,
    acquisition_channels.dt_opportunity,
    acquisition_channels.dt_first_listing,
    acquisition_channels.dt_discarded,
    acquisition_channels.user_id_lead_first_discarder,
    acquisition_channels.user_id_lead_last_discarder,
    acquisition_channels.flow,
    acquisition_channels.acquisition_method,
    acquisition_channels.acquisition_channel,
    acquisition_channels.acquisition_source,
    acquisition_channels.funnel_step,
    acquisition_channels.hours_lead_to_prospect,
    acquisition_channels.hours_prospect_to_qualified,
    acquisition_channels.hours_lead_to_first_inside_sales_contact,
    acquisition_channels.hours_prospect_to_first_inside_sales_contact,
    acquisition_channels.hours_qualified_to_opportunity,
    acquisition_channels.hours_opportunity_to_listing,
    acquisition_channels.hours_lead_to_listing,
    acquisition_channels.days_lead_to_prospect,
    acquisition_channels.days_prospect_to_qualified,
    acquisition_channels.days_lead_to_first_inside_sales_contact,
    acquisition_channels.days_prospect_to_first_inside_sales_contact,
    acquisition_channels.days_qualified_to_opportunity,
    acquisition_channels.days_opportunity_to_listing,
    acquisition_channels.days_lead_to_listing,
    acquisition_channels.days_lead_to_processing,
    acquisition_channels.acquisition_channel_rep,
    acquisition_channels.origin_lead_usuario_que_indicou_id,
    acquisition_channels.acquisition_channel_rep !~~ 'Reprocessed%' as is_not_reprocessed,
    acquisition_channels.is_b2b
  from acquisition_channels
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
  from fact_with_reproc f
  left join legacy_doorman d 
    on f.imovel_id = d.imovel_id
), 
leads_b2b as (
  select distinct
    l.id as id_lead,
    pa_b2b_online.partner_id as online_partner_id,
    pa_b2b_prime.partner_id as prime_partner_id
  from lead l
  left join usuario u_b2b_prime 
    on u_b2b_prime.telefone_principal = l.telefone_anunciante
  left join partner_agent pa_b2b_prime 
    on pa_b2b_prime.user_id = u_b2b_prime.id
  left join partner_agent pa_b2b_online 
    on pa_b2b_online.user_id = l.usuario_que_indicou_id
  where coalesce(pa_b2b_online.partner_id, pa_b2b_prime.partner_id) is not null
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
    coalesce(pa_b2b_prime.partner_id, l_b2b.online_partner_id, l_b2b.prime_partner_id, '-1'::integer::bigint) as sk_partner,
    coalesce(to_char(f.dt_lead::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_lead_date,
    coalesce(to_char(f.dt_prospect::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_prospect_date,
    coalesce(to_char(btf.dt_created::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_first_task_created_date,
    coalesce(to_char(btf.dt_closed::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_first_task_closed_date,
    coalesce(to_char(btl.dt_created::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_last_task_created_date,
    coalesce(to_char(btl.dt_closed::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_last_task_closed_date,
    coalesce(to_char(f.dt_first_inside_sales_contact::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_first_inside_sales_contact_date,
    coalesce(to_char(f.dt_conversion::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_conversion_date,
    coalesce(to_char(f.dt_qualified::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_qualified_date,
    coalesce(to_char(f.dt_opportunity::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_opportunity_date,
    coalesce(to_char(f.dt_first_listing::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_first_listing_date,
    coalesce(to_char(f.dt_discarded::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_discard_date,
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
    f.hours_lead_to_first_inside_sales_contact,
    f.hours_prospect_to_first_inside_sales_contact,
    f.hours_qualified_to_opportunity,
    f.hours_opportunity_to_listing,
    f.hours_lead_to_listing,
    f.days_lead_to_prospect,
    f.days_prospect_to_qualified,
    f.days_lead_to_first_inside_sales_contact,
    f.days_prospect_to_first_inside_sales_contact,
    f.days_qualified_to_opportunity,
    f.days_opportunity_to_listing,
    f.days_lead_to_listing,
    f.days_lead_to_processing,
    h.exclusivity as is_exclusive,
    case
      when btf.rep_id is not null then 'Lead'
      when coalesce(bpt.imovel_id, f.rep_id) is not null then 'Photojob'
      else null
    end as first_isales_intervention,
    bl.lead_type,
    bl.lead_origin,
    coalesce(lfet.tracking_source, bl.utm_source) as utm_source,
    coalesce(lfet.tracking_medium, bl.utm_medium) as utm_medium,
    lfet.tracking_platform,
    coalesce(lower(btrim(lfet.tracking_campaign)) ~* '(institucional)|(branded)',
             bl.branded_lead) as is_branded,
    (bl.b2b_lead or f.is_b2b) as is_b2b, -- Using business rules for both constraints of old b2b and new one
    bl.reprocessed_flg,
    a.is_doorman,
    f.acquisition_channel_rep = 'Inside Sales' as is_isales_direct_register,
    f.acquisition_channel_rep = 'Admin' as is_cx_direct_register,
    coalesce(f.rep_id, btf.rep_id, bpt.imovel_id) is not null as has_isales_intervention,
    us_cad.id is not null as is_call_center,
    lfet.tracking_referring_domain as lead_referring_domain,
    us_d.subscriptionSource as subscription_source,
    case when ua.affiliateType = 'Doorman' and u.dados_agente_id is not null then 'Doorman & Agent'
		 when u.dados_agente_id is not null then 'Agent'
		 else ua.affiliateType end as affiliate_type
  from fact_with_reproc f
  left join lead_first_event_tracking lfet 
    on lfet.id_lead = f.lead_id
  left join acquisitions a 
    on a.id = f.id
  left join base_lead_tasks_first btf
    on btf.lead_id = f.lead_id
  left join base_lead_tasks_last btl
    on btl.lead_id = f.lead_id
  left join base_photo_tasks bpt 
    on f.imovel_id = bpt.imovel_id
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
    lead_referring_domain,
    subscription_source,
    is_branded::integer::boolean as is_branded,
    is_b2b::integer::boolean as is_b2b,
    is_isales_direct_register::integer::boolean as is_isales_direct_register,
    is_cx_direct_register::integer::boolean as is_cx_direct_register,
    has_isales_intervention::integer::boolean as has_isales_intervention,
    is_call_center::integer::boolean as is_call_center,
    mkt_origin,
    mkt_channel,
    mkt_medium,
    mkt_source
  from files.taxonomy_growth
),
applied_taxonomy as (
select 
  pl.*,
  case
    when pl.is_branded then 'Branded'
    else 'Other'
  end as mkt_branded,
  case
    when t.mkt_origin is null then 'Other'
    else t.mkt_origin
  end as mkt_origin,
  case
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
    when t.mkt_origin is null then 'Not Mapped'
    else t.mkt_medium
  end as mkt_medium,
  case
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
    and coalesce(pl.lead_referring_domain, '') = coalesce(t.lead_referring_domain, '')
    and coalesce(pl.subscription_source, '') = coalesce(t.subscription_source, '')
    and coalesce(pl.is_branded, false) = coalesce(t.is_branded, false) 
    and coalesce(pl.is_b2b, false) = coalesce(t.is_b2b, false)
    and coalesce(pl.is_isales_direct_register, false) = coalesce(t.is_isales_direct_register, false) 
    and coalesce(pl.is_cx_direct_register, false) = coalesce(t.is_cx_direct_register, false) 
    and coalesce(pl.has_isales_intervention, false) = coalesce(t.has_isales_intervention, false) 
    and coalesce(pl.is_call_center, false) = coalesce(t.is_call_center, false)
),
applied_taxonomy_flow as (
    select
        *,
        case
             when lead_type = 'Proparceria' then 'Non Self-Service'
             when lead_type = 'Marketing' and lead_origin in ('Facebook', 'Reprocessado') then 'Non Self-Service'
             when (is_cx_direct_register or is_isales_direct_register) then 'Non Self-Service'
             when lead_origin = 'Landing' then 'Non Self-Service'
             when mkt_origin in ('Owner PWA', 'Price Calculator') then 'Self-Service'
             when mkt_origin in ('Indica Aí - Agents', 'Indica Aí - General')
                  and mkt_source = 'Direct Referral' then 'Self-Service'
             when mkt_origin in ('Other', 'Not Mapped') then mkt_origin
             else 'Non Self-Service' end as mkt_flow
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
  atax.sk_prospect_date,
  atax.sk_first_task_created_date,
  atax.sk_first_task_closed_date,
  atax.sk_last_task_created_date,
  atax.sk_last_task_closed_date,
  atax.sk_first_inside_sales_contact_date,
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
  atax.hours_lead_to_first_inside_sales_contact,
  atax.hours_prospect_to_first_inside_sales_contact,
  atax.hours_qualified_to_opportunity,
  atax.hours_opportunity_to_listing,
  atax.hours_lead_to_listing,
  atax.days_lead_to_prospect,
  atax.days_prospect_to_qualified,
  atax.days_lead_to_first_inside_sales_contact,
  atax.days_prospect_to_first_inside_sales_contact,
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
  atax.has_isales_intervention,
  atax.is_call_center,
  atax.reprocessed_flg as is_lead_reprocessed,
  atax.affiliate_type,
  atax.lead_referring_domain,
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