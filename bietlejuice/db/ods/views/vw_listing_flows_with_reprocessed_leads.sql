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
     max((business_context = 'RENT')::integer)::boolean as is_for_rent,
     max(
        case 
          when lbc.business_context = 'SALE' then lbc.status
          end)
     as status_sale,
     max(
        case 
          when lbc.business_context = 'RENT' then lbc.status
          end)
     as status_rent,
     max(
        case 
          when lbc.business_context = 'SALE' then lbc.ts_created
          end)
     as dt_qualified_sale,
     max(
        case 
          when lbc.business_context = 'RENT' then lbc.ts_created
          end)
     as dt_qualified_rent,
     max(
        case 
          when lbc.business_context = 'SALE' then lbc.ts_first_listing
          end)
     as dt_first_listing_sale,
     max(
        case 
          when lbc.business_context = 'RENT' then lbc.ts_first_listing
          end)
     as dt_first_listing_rent,
     max(
        case 
          when lbc.business_context = 'SALE' then lbc.ts_opt_out_sale
          end)
     as dt_opt_out_sale,
     max(
        case 
          when lbc.business_context = 'RENT' then lbc.ts_opt_out_rent
          end)
     as dt_opt_out_rent,
     max(
        case 
          when lbc.business_context = 'SALE' then lbc.user_listing_registrant_sale
          end)
     as user_registrant_sale,
     max(
        case 
          when lbc.business_context = 'RENT' then lbc.user_listing_registrant_rent
          end)
     as user_registrant_rent
    from
       listing_business_context lbc
    group by 1
),
first_job AS 
(SELECT 
  imovel_id,
  min(id) as id_job
FROM photo_job
WHERE creation_origin <> 'Prop'
GROUP by imovel_id),
acquisition_channels as (
    select
        fhlf.id,
        fhlf.lead_id,
        fhlf.conversao_id,
        fhlf.photo_job_id,
        fhlf.imovel_id,
        case
            when (lbc.user_registrant_rent = h.usuario_id and u.tipo_admin = 'Normal' and (u.email not like '%quintoandar%' or u.email not like '%actionline%'))
            then fpj.rep_id
        else lbc.user_registrant_rent
        end as rep_id,
        fhlf.isales_registrant_id,
        fhlf.affiliate_id,
        fhlf.region_id,
        case
            when l.is_for_rent::int::boolean
            then fhlf.dt_lead
            else lbc.dt_qualified_rent
        end as dt_lead,
        case
            when l.is_for_rent::int::boolean
            then fhlf.dt_prospect
            else lbc.dt_qualified_rent
        end as dt_prospect,
        case
            when l.is_for_rent::int::boolean
            then fhlf.dt_first_contact
            else lbc.dt_qualified_rent
        end as dt_first_contact,
        fhlf.dt_conversion,
        case 
           when (coalesce(l.reason_detail, l.reason) = 'ProprietarioRecusou' and l.reason != 'OWNER_DIDNT_LISTEN_TO_PITCH' and fhlf.conversao_id IS NULL) then fhlf.dt_qualified
           else lbc.dt_qualified_rent 
        end as dt_qualified,
        case
           when (lbc.dt_opt_out_rent < fhlf.dt_opportunity and lbc.status_rent = 'OPTED_OUT')
           then null
           when (fhlf.dt_opportunity >= lbc.dt_qualified_rent and (lbc.dt_first_listing_rent is null or fhlf.dt_opportunity <= lbc.dt_first_listing_rent))
           then fhlf.dt_opportunity
           when lbc.dt_first_listing_rent is not null
           then lbc.dt_first_listing_rent
         end as dt_opportunity,
        lbc.dt_first_listing_rent as dt_first_listing,
        fhlf.dt_discarded,
        lsc.ts_sales_company_sent,
        fhlf.user_id_lead_first_discarder,
        fhlf.user_id_lead_last_discarder,
        fhlf.is_self_service_photo_job_scheduled,
        fhlf.flow,
        fhlf.acquisition_method,
        fhlf.acquisition_channel,
        fhlf.acquisition_source,
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
        coalesce(rl.lead_agent_id, l.lead_agent_id) is not null as is_agent_referral,
        l.status as lead_status,
        coalesce(l.reason_detail, l.reason) as lead_reason,
        l.cidade,
        pj.job_status as photo_job_status,
        pj.photographer_problem_reason as photo_job_reason,
        lbc.dt_opt_out_rent,
        case 
            when l.is_for_sale::int::boolean and l.is_for_rent::int::boolean then 'Hybrid'
            when l.is_for_rent::int::boolean then 'Only Rent'
            when l.is_for_sale::int::boolean then 'Only Sale'
            else 'Organic'
        end as lead_context_origin,
        case 
            when lbc.status_sale is null then 'Not Qualified Yet'
            when lbc.status_sale = 'EDITING' then 'Editing'
            when lbc.status_sale = 'OPTED_OUT' then 'Opted Out'
            else 'Once Published'
        end as listing_sale_status
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
    left join public.usuario u 
        on u.id = lbc.user_registrant_rent
    left join public.photo_job pj
        on fhlf.photo_job_id = pj.id
    left join first_job
        on first_job.imovel_id = h.id
    left join photo_job fpj
        on first_job.id_job = fpj.id
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
    case
        when (dt_first_listing is not null) then 'Listed'
        when (dt_opportunity is not null and dt_first_listing is null) and photo_job_status in ('FotosTiradas','Completado', 'NaoListado') then 'NotListedYet'
        when (dt_opportunity is not null and dt_opt_out_rent >= dt_opportunity and dt_first_listing is null) and photo_job_status in ('FotosTiradas','Completado', 'NaoListado') then 'OptedOut Opportunity'
        when (dt_opportunity is not null and dt_first_listing is null and photo_job_status in ('Agendado','Iniciado','Novo')) then 'PhotoJobScheduled'
        when (dt_opportunity is not null and dt_first_listing is null and photo_job_status = 'Cancelado') then coalesce(photo_job_reason, 'CancelledPhotoJob')
        when (dt_opportunity is not null and dt_first_listing is null) then coalesce(photo_job_reason, 'CancelledPhotoJob')
        when (dt_opportunity is null and dt_qualified is not null and lead_status = 'Descartado') then 'DiscardedQualified'
        when (dt_opportunity is null and dt_qualified is not null and lead_status = 'Convertido') then 'NoPhotoJob'
        when (dt_opportunity is null and dt_qualified is not null and conversao_id is not null) then 'NoPhotoJob'
        when (dt_opportunity is null and dt_qualified is not null and dt_opt_out_rent >= dt_qualified) then 'OptedOut Qualified'
        when (dt_opportunity is null and lead_reason = 'EmProspeccao') then 'OnHold'
        when (dt_qualified is null and lead_status = 'Descartado') then 'DiscardedProspect'
        when (dt_qualified is null and lead_status = 'Novo' and cidade = 'Outra cidade') then 'NaoProcessadoArea'
        when (dt_qualified is null and lead_status = 'Novo') then 'NaoProcessado'
        when (flow = 'Lead Flow' and dt_qualified is null) then 'NaoProcessado'
        when (lead_status = 'Convertido' and conversao_id is null) then 'BrokenLeadFlow'
        when (flow = 'Lead Flow' and dt_prospect is null and lead_status is null) then 'DiscardedLead'
        when (flow = 'Self-Service Flow' and dt_prospect is not null and dt_qualified is null) then 'TermsNotAccepted'
        when (flow = 'Self-Service Flow' and dt_qualified is not null and dt_opportunity is null) then 'NoPhotoJob'
        when (flow = 'Organic Flow' and dt_prospect is not null and dt_qualified is null) then 'UnfinishedForm'
        when (flow = 'Organic Flow' and dt_qualified is not null and dt_opportunity is null) then 'NoPhotoJob'
        else 'NotMapped'
    end as funnel_step,
    ((date_part('hour', dt_prospect - dt_lead) * 60 +
      date_part('minute', dt_prospect - dt_lead)) / 60.)::numeric(14,2) as hours_lead_to_prospect,
    ((date_part('hour', dt_qualified - dt_prospect) * 60 +
      date_part('minute', dt_qualified - dt_prospect)) / 60.)::numeric(14,2) as hours_prospect_to_qualified,
    ((date_part('hour', dt_first_contact - dt_lead) * 60 +
      date_part('minute', dt_first_contact - dt_lead)) / 60.)::numeric(14,2) as hours_lead_to_first_contact,
    ((date_part('hour', dt_first_contact - dt_prospect) * 60 +
      date_part('minute', dt_first_contact - dt_prospect)) / 60.)::numeric(14,2) as hours_prospect_to_first_contact,
    ((date_part('hour', dt_opportunity - dt_qualified) * 60 +
      date_part('minute', dt_opportunity - dt_qualified)) / 60.)::numeric(14,2) as hours_qualified_to_opportunity,    
    ((date_part('hour', dt_first_listing - dt_opportunity) * 60 +
      date_part('minute', dt_first_listing - dt_opportunity)) / 60.)::numeric(14,2) as hours_opportunity_to_listing,
    ((date_part('hour', dt_first_listing - dt_lead) * 60 +
      date_part('minute', dt_first_listing - dt_lead)) / 60.)::numeric(14,2) as hours_lead_to_listing,
    ((date_part('day', dt_prospect - dt_lead) * 1440 +
      date_part('hour', dt_prospect - dt_lead) * 60 +
      date_part('minute', dt_prospect - dt_lead)) / 1440.)::numeric(14,2) as days_lead_to_prospect,    
    ((date_part('day', dt_qualified - dt_prospect) * 1440 +
      date_part('hour', dt_qualified - dt_prospect) * 60 +
      date_part('minute', dt_qualified - dt_prospect)) / 1440.)::numeric(14,2) as days_prospect_to_qualified,
    ((date_part('day', dt_first_contact - dt_lead) * 1440 +
      date_part('hour', dt_first_contact - dt_lead) * 60 +
      date_part('minute', dt_first_contact - dt_lead)) / 1440.)::numeric(14,2) as days_lead_to_first_contact,
    ((date_part('day', dt_first_contact - dt_prospect) * 1440 +
      date_part('hour', dt_first_contact - dt_prospect) * 60 +
      date_part('minute', dt_first_contact - dt_prospect)) / 1440.)::numeric(14,2) as days_prospect_to_first_contact,
    ((date_part('day', dt_opportunity - dt_qualified) * 1440 +
      date_part('hour', dt_opportunity - dt_qualified) * 60 +
      date_part('minute', dt_opportunity - dt_qualified)) / 1440.)::numeric(14,2) as days_qualified_to_opportunity,
    ((date_part('day', dt_first_listing - dt_opportunity) * 1440 +
      date_part('hour', dt_first_listing - dt_opportunity) * 60 +
      date_part('minute', dt_first_listing - dt_opportunity)) / 1440.)::numeric(14,2) as days_opportunity_to_listing,
    ((date_part('day', dt_first_listing - dt_lead) * 1440 +
      date_part('hour', dt_first_listing - dt_lead) * 60 +
      date_part('minute', dt_first_listing - dt_lead)) / 1440.)::numeric(14,2) as days_lead_to_listing,
    case 
      when (dt_conversion is null and dt_discarded is null) then null 
      else
        ((date_part('day', least(coalesce(dt_conversion, dt_discarded + INTERVAL '1 DAY'), 
            coalesce(dt_discarded, dt_conversion + INTERVAL '1 DAY')) - dt_lead) * 1440 +
        date_part('hour', least(coalesce(dt_conversion, dt_discarded + INTERVAL '1 DAY'), 
            coalesce(dt_discarded, dt_conversion + INTERVAL '1 DAY')) - dt_lead) * 60 +
        date_part('minute', least(coalesce(dt_conversion, dt_discarded + INTERVAL '1 DAY'), 
            coalesce(dt_discarded, dt_conversion + INTERVAL '1 DAY')) - dt_lead)) / 1440.)::numeric(14,2)
    end as days_lead_to_processing,
    acquisition_channels.acquisition_channel_rep,
    acquisition_channels.origin_lead_usuario_que_indicou_id,
    acquisition_channels.acquisition_channel_rep !~~ 'Reprocessed%' as is_not_reprocessed,
    acquisition_channels.is_b2b,
    acquisition_channels.partner_id,
    acquisition_channels.affiliate_type,
    acquisition_channels.is_agent_referral,
    acquisition_channels.dt_opt_out_rent,
    acquisition_channels.lead_context_origin,
    acquisition_channels.listing_sale_status
from
    acquisition_channels;
