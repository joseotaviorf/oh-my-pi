--drop view if exists vw_sales_potential_listings;
--create or replace view vw_sales_potential_listings as
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
  left join public.photo_job pj
    on pt.origin_id = pj.id
  left join public.house h
    on h.id = pj.imovel_id
  left join public.house h_direct
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
    lead.codigo_imobiliaria is not null OR lead.flg_b2b as b2b_lead
    from lead
),
base_leads_reproc as (
  select
    lead.id as lead_id,
    lead.tipo as lead_type,
    lead.origem as lead_origin,
    lead.utm_source,
    lead.utm_medium,
    coalesce(lower(btrim(lead.utm_campaign)) ~* '(institucional)|(branded)' and lower(btrim(lead.utm_campaign)) !~* '(non-branded)', false) as branded_lead,
    lead.codigo_imobiliaria is not null OR lead.flg_b2b as b2b_lead,
  	rl.id_origin_lead as old_lead_id
    from lead
    join reprocessed_lead rl
  	  on rl.id = lead.id
    where lead.origem = 'Reprocessado'
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
    left join base_leads_reproc old_bl
      on old_bl.old_lead_id = bl.lead_id
    group by 1,2,3,4,5,6,7,8
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
  from sales_listing_flows_with_reprocessed_leads f
  left join legacy_doorman d
    on f.imovel_id = d.imovel_id
),
leads_b2b as (
  select distinct
    l.id as id_lead,
    pa_b2b_online.partner_id as online_partner_id
  from public.lead l
  left join public.partner_agent pa_b2b_online
    on pa_b2b_online.user_id = l.usuario_que_indicou_id
  where pa_b2b_online.partner_id is not null
)
select 
  f.id as sk_house_listing_flow,
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
  coalesce(dr.city_id, '-1'::integer) as id_city,
  coalesce(pa_b2b_prime.partner_id, l_b2b.online_partner_id, '-1'::integer::bigint) as sk_partner,
  coalesce(to_char(f.dt_lead::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_lead_date,
  coalesce(to_char(f.dt_prospect::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_prospect_date,
  coalesce(to_char(CASE WHEN btf.dt_created < f.dt_lead THEN f.dt_lead ELSE btf.dt_created END::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_first_task_created_date,
  coalesce(to_char(CASE WHEN btf.dt_closed < f.dt_lead THEN f.dt_lead ELSE btf.dt_closed END::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_first_task_closed_date,
  coalesce(to_char(CASE WHEN btl.dt_created < f.dt_lead THEN f.dt_lead ELSE btl.dt_created END::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_last_task_created_date,
  coalesce(to_char(CASE WHEN btl.dt_closed < f.dt_lead THEN f.dt_lead ELSE btl.dt_closed END::date::timestamp with time zone, 'YYYYMMDD')::integer, '-1'::integer) as sk_last_task_closed_date,
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
    when f.dt_first_contact is not null then 'first contact'
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
  (bl.b2b_lead or f.is_b2b) as is_b2b, -- Using business rules for both constraints of old b2b and new one
  bl.reprocessed_flg,
  a.is_doorman,
  f.acquisition_channel_rep = 'Inside Sales' as is_isales_direct_register,
  f.acquisition_channel_rep = 'Admin' as is_cx_direct_register,
  (f.acquisition_channel_rep = 'Inside Sales') or (f.acquisition_channel_rep = 'Admin') as is_ops_direct_register,
  coalesce(f.isales_registrant_id, btf.rep_id) is not null
  or (bpt.has_job_photo = true and not f.is_self_service_photo_job_scheduled)
      as has_isales_intervention,
  bpt.has_fup_photo as has_fup_photo_task,
  lfet.tracking_referring_domain as lead_referring_domain,
  case
    when lower(lfet.tracking_referring_domain) LIKE '%corretor%' THEN 'Agents'
    when lower(lfet.tracking_referring_domain) LIKE '%indicaai%' THEN 'Indica Ai'
    when lower(lfet.tracking_referring_domain) LIKE '%proprietario%' THEN 'Owner'
    else 'Other'
  end as lead_referring_category,
  f.lead_id,
  f.affiliate_type as listing_flows_affiliate_type,
  coalesce(f.affiliate_id, f.origin_lead_usuario_que_indicou_id::integer, '-1'::integer) as affiliate_id,
	f.is_agent_referral,
  coalesce(f.region_id, -1) as region_id,
  h.usuario_que_cadastrou_id as house_usuario_que_cadastrou_id,
  f.dt_opt_out_sale as ts_opt_out_sale,
  f.lead_context_origin,
  f.listing_rent_status
from sales_listing_flows_with_reprocessed_leads f
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
left join public.house h
  on f.imovel_id = h.id
left join staging.dim_region dr 
  on dr.sk_region = f.region_id
left join leads_b2b l_b2b 
  on l_b2b.id_lead = f.lead_id
left join public.partner_agent pa_b2b_prime
  on h.usuario_id = pa_b2b_prime.user_id
left join public.house_listing hl_version_zero
  on hl_version_zero.id_house = f.imovel_id
    and hl_version_zero.version = 0
