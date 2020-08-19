--drop view if exists sale.vw_fact_listing_flows;
--create or replace view sale.vw_fact_listing_flows as
with lead_city_region as (
  with city_region as (
    select 
      region.id as id_region,
      regexp_replace(remove_accentuation(lower(region.nome)), '[^a-z]+', '', 'g') as formatted_city
    from public.region
    where region.nivel = 'Cidade'
  )
  select 
    l.id,
    r.id_region
  from public.lead l
  join city_region r 
    on r.formatted_city = regexp_replace(remove_accentuation(lower(l.cidade)), '[^a-z]+', '', 'g')
), 
potential_listings_enrich as (
    select
        p.*,
        coalesce(p.id_city, lcr.id_region, '-1'::integer) as sk_city,
        us_cad.id is not null as is_call_center,
        us_d.subscriptionSource as subscription_source,
        coalesce(p.listing_flows_affiliate_type,
            case when ua.affiliateType = 'Doorman' and u.dados_agente_id is not null then 'Doorman & Agent'
                 when u.dados_agente_id is not null then 'Agent'
                 else ua.affiliateType
            end) as affiliate_type
    from sales_potential_listings p
    left join usuario us_cad
      on us_cad.id = p.house_usuario_que_cadastrou_id
        and us_cad.email ~~ '%@hargos.com.br'
    left join usuario u
   	  on u.id = p.affiliate_id
    left join user_doorman us_d
      on us_d.id_dados_afiliado = u.dados_afiliado_id
    left join user_affiliate ua
      on ua.id = u.dados_afiliado_id
    left join lead_city_region lcr
      on p.region_id = -1 and p.lead_id = lcr.id
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
    gsheets.taxonomy_growth
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
from potential_listings_enrich pl
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
  atax.ts_opt_out_sale,
  atax.lead_context_origin,
  atax.listing_rent_status,
  atax.ts_load
from applied_taxonomy_flow atax
