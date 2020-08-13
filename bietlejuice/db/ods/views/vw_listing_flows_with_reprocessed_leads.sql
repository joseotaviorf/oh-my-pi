drop view if exists vw_listing_flows_with_reprocessed_leads;

create or replace view vw_listing_flows_with_reprocessed_leads as
with reproc_leads as (
    select
        rl.id,
        l.origem,
        l.tipo,
        l.usuario_que_indicou_id,
        l.lead_agent_id,
        l.affiliate_type
    from
        reprocessed_lead rl
    join lead l
        on l.id = rl.id_origin_lead
),
lbc as (
    select id_house,
        max((business_context = 'SALE')::integer)::boolean as is_for_sale,
        max((business_context = 'RENT')::integer)::boolean as is_for_rent
    from
        listing_business_context
    group by 1
),
acquisition_channels as (
    select
        fhlf.id,
        fhlf.lead_id,
        fhlf.conversao_id,
        fhlf.photo_job_id,
        fhlf.imovel_id,
        fhlf.rep_id,
        fhlf.isales_registrant_id,
        fhlf.affiliate_id,
        fhlf.region_id,
        fhlf.dt_lead,
        fhlf.dt_prospect,
        fhlf.dt_first_contact,
        fhlf.dt_conversion,
        fhlf.dt_qualified,
        fhlf.dt_opportunity,
        fhlf.dt_first_listing,
        fhlf.dt_discarded,
        lsc.ts_sales_company_sent,
        fhlf.user_id_lead_first_discarder,
        fhlf.user_id_lead_last_discarder,
        fhlf.is_self_service_photo_job_scheduled,
        fhlf.flow,
        fhlf.acquisition_method,
        fhlf.acquisition_channel,
        fhlf.acquisition_source,
        fhlf.funnel_step,
        fhlf.hours_lead_to_prospect,
        fhlf.hours_prospect_to_qualified,
        fhlf.hours_lead_to_first_contact,
        fhlf.hours_prospect_to_first_contact,
        fhlf.hours_qualified_to_opportunity,
        fhlf.hours_opportunity_to_listing,
        fhlf.hours_lead_to_listing,
        fhlf.days_lead_to_prospect,
        fhlf.days_prospect_to_qualified,
        fhlf.days_lead_to_first_contact,
        fhlf.days_prospect_to_first_contact,
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
            coalesce(rl.affiliate_type, l.affiliate_type) = 'B2BPartner'
            or coalesce(pa_b2b.id, b2b_prime_draft.id_lead) is not null
            , false) as is_b2b,
        b2b_prime_draft.partner_id,
        coalesce(rl.affiliate_type, l.affiliate_type) as affiliate_type,
        coalesce(rl.lead_agent_id, l.lead_agent_id) is not null as is_agent_referral
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
        select
            l.id as id_lead,
            max(pa_b2b.partner_id) as partner_id
        from
            lead l
        join usuario u_b2b
            on u_b2b.telefone_principal = l.telefone_anunciante
        join partner_agent pa_b2b
            on pa_b2b.user_id = u_b2b.id
        where
            l.origem = 'OwnerPWA'
        group by 1
    ) b2b_prime_draft
        on b2b_prime_draft.id_lead = l.id
    left join house_listing hl
        on hl.id_house = fhlf.imovel_id
        and hl.version = 0
    left join lbc
        on lbc.id_house = h.id
    left join lead_sales_company lsc
        on lsc.id_lead = l.id
    where
        (lbc.id_house is null and h.id is not null) -- When house is not in listing_business_context, it is for rent
        or lbc.is_for_rent
        or l.is_for_rent::int::boolean
)
select
    acquisition_channels.id,
    acquisition_channels.lead_id,
    acquisition_channels.conversao_id,
    acquisition_channels.photo_job_id,
    acquisition_channels.imovel_id,
    acquisition_channels.rep_id,
    acquisition_channels.isales_registrant_id,
    acquisition_channels.affiliate_id,
    acquisition_channels.region_id,
    acquisition_channels.dt_lead,
    acquisition_channels.dt_prospect,
    acquisition_channels.dt_first_contact,
    acquisition_channels.dt_conversion,
    acquisition_channels.dt_qualified,
    acquisition_channels.dt_opportunity,
    acquisition_channels.dt_first_listing,
    acquisition_channels.dt_discarded,
    acquisition_channels.ts_sales_company_sent,
    acquisition_channels.user_id_lead_first_discarder,
    acquisition_channels.user_id_lead_last_discarder,
    acquisition_channels.is_self_service_photo_job_scheduled,
    acquisition_channels.flow,
    acquisition_channels.acquisition_method,
    acquisition_channels.acquisition_channel,
    acquisition_channels.acquisition_source,
    acquisition_channels.funnel_step,
    acquisition_channels.hours_lead_to_prospect,
    acquisition_channels.hours_prospect_to_qualified,
    acquisition_channels.hours_lead_to_first_contact,
    acquisition_channels.hours_prospect_to_first_contact,
    acquisition_channels.hours_qualified_to_opportunity,
    acquisition_channels.hours_opportunity_to_listing,
    acquisition_channels.hours_lead_to_listing,
    acquisition_channels.days_lead_to_prospect,
    acquisition_channels.days_prospect_to_qualified,
    acquisition_channels.days_lead_to_first_contact,
    acquisition_channels.days_prospect_to_first_contact,
    acquisition_channels.days_qualified_to_opportunity,
    acquisition_channels.days_opportunity_to_listing,
    acquisition_channels.days_lead_to_listing,
    acquisition_channels.days_lead_to_processing,
    acquisition_channels.acquisition_channel_rep,
    acquisition_channels.origin_lead_usuario_que_indicou_id,
    acquisition_channels.acquisition_channel_rep !~~ 'Reprocessed%' as is_not_reprocessed,
    acquisition_channels.is_b2b,
    acquisition_channels.partner_id,
    acquisition_channels.affiliate_type,
    acquisition_channels.is_agent_referral
from
    acquisition_channels;
