--drop view if exists vw_sales_listing_flows_with_reprocessed_leads;
--create or replace view vw_sales_listing_flows_with_reprocessed_leads as
WITH reproc_leads AS (
    SELECT 
      rl.id,
      l.origem,
      l.tipo,
      l.usuario_que_indicou_id,
      l.lead_agent_id,
      l.affiliate_type
    FROM reprocessed_lead rl
    JOIN public.lead l
      ON l.id = rl.id_origin_lead
  ),
  lbc AS (
    SELECT id_house,
     MAX((business_context = 'SALE')::INTEGER)::BOOLEAN AS is_for_sale,
     MAX((business_context = 'RENT')::INTEGER)::BOOLEAN AS is_for_rent,
     MAX(
        CASE
          WHEN lbc.business_context = 'SALE' THEN lbc.status
          END)
     AS status_sale,
     MAX(
        CASE
          WHEN lbc.business_context = 'RENT' THEN lbc.status
          END)
     AS status_rent,
     MAX(
        CASE
          WHEN lbc.business_context = 'SALE' THEN lbc.ts_created
          END)
     AS dt_qualified_sale,
     MAX(
        CASE
          WHEN lbc.business_context = 'RENT' THEN lbc.ts_created
          END)
     AS dt_qualified_rent,
     MAX(
        CASE
          WHEN lbc.business_context = 'SALE' THEN lbc.ts_first_listing
          END)
     AS dt_first_listing_sale,
     MAX(
        CASE
          WHEN lbc.business_context = 'RENT' THEN lbc.ts_first_listing
          END)
     AS dt_first_listing_rent,
     MAX(
        CASE
          WHEN lbc.business_context = 'SALE' THEN lbc.ts_opt_out_sale
          END)
     AS dt_opt_out_sale,
     MAX(
        CASE
          WHEN lbc.business_context = 'RENT' THEN lbc.ts_opt_out_rent
          END)
     AS dt_opt_out_rent,
     MAX(
        CASE
          WHEN lbc.business_context = 'SALE' THEN lbc.user_listing_registrant_sale
          END)
     AS user_registrant_sale,
     MAX(
        CASE
          WHEN lbc.business_context = 'RENT' THEN lbc.user_listing_registrant_rent
          END)
     AS user_registrant_rent
    FROM
       listing_business_context lbc
    GROUP BY 1
  ),
  first_job AS (
    SELECT
     imovel_id,
     MIN(id) AS id_job
    FROM photo_job
    WHERE 
     creation_origin <> 'Prop'
    GROUP by imovel_id
  ),
  b2b_prime_draft AS (
    SELECT
     l.id AS id_lead,
     MAX(pa_b2b.partner_id) AS partner_id
    FROM
     lead AS l
    JOIN usuario AS u_b2b
     ON u_b2b.telefone_principal = l.telefone_anunciante
    JOIN partner_agent AS pa_b2b
     ON pa_b2b.user_id = u_b2b.id
    LEFT JOIN partner p_b2b
     ON p_b2b.id = pa_b2b.partner_id
    WHERE 
     l.origem = 'OwnerPWA' 
     AND p_b2b.type = 'PRIME'
    GROUP BY 1
  ),
  pa_b2b AS (
    SELECT 
      pa.*
    FROM partner_agent pa
    LEFT JOIN partner p_b2b
      ON p_b2b.id = pa.partner_id
    WHERE 
      p_b2b."type" = 'PRIME'
  ),
  acquisition_channels AS (
    SELECT 
      fhlf.id,
      fhlf.lead_id,
      fhlf.conversao_id,
      fhlf.photo_job_id,
      fhlf.imovel_id,
      CASE
          WHEN (lbc.user_registrant_sale = h.usuario_id AND u.tipo_admin = 'Normal' AND (u.email NOT LIKE '%quintoandar%' OR u.email NOT LIKE '%actionline%'))
          THEN fpj.rep_id
          ELSE lbc.user_registrant_sale
      END AS rep_id,
      fhlf.isales_registrant_id,
      fhlf.affiliate_id,
      fhlf.region_id,
      CASE
          WHEN l.is_for_sale::INT::BOOLEAN
          THEN fhlf.dt_lead
          ELSE lbc.dt_qualified_sale
      END AS dt_lead,
      CASE
          WHEN l.is_for_sale::INT::BOOLEAN
          THEN fhlf.dt_prospect
          ELSE lbc.dt_qualified_sale
      END AS dt_prospect,
      CASE
          WHEN l.is_for_sale::INT::BOOLEAN
          THEN fhlf.dt_first_contact
          ELSE lbc.dt_qualified_sale
      END AS dt_first_contact,
      fhlf.dt_conversion,
      CASE
         WHEN (COALESCE(lr.reason, l.reason) = 'ProprietarioRecusou' AND l.reason != 'OWNER_DIDNT_LISTEN_TO_PITCH' AND fhlf.conversao_id IS NULL) THEN fhlf.dt_qualified
         ELSE lbc.dt_qualified_sale 
      END AS dt_qualified,
      CASE
         WHEN (lbc.dt_opt_out_sale < fhlf.dt_opportunity AND lbc.status_sale = 'OPTED_OUT')
         THEN NULL
         WHEN (fhlf.dt_opportunity >= lbc.dt_qualified_sale AND (lbc.dt_first_listing_sale IS NULL or fhlf.dt_opportunity <= lbc.dt_first_listing_sale))
         THEN fhlf.dt_opportunity
         WHEN lbc.dt_first_listing_sale IS NOT NULL
         THEN lbc.dt_first_listing_sale
      END AS dt_opportunity,
      lbc.dt_first_listing_sale AS dt_first_listing,
      fhlf.dt_discarded,
      lsc.ts_sales_company_sent,
      fhlf.user_id_lead_first_discarder,
      fhlf.user_id_lead_last_discarder,
      fhlf.is_self_service_photo_job_scheduled,
      fhlf.flow,
      fhlf.acquisition_method,
      fhlf.acquisition_channel,
      fhlf.acquisition_source,
      CASE
        WHEN l.origem = 'Reprocessado' AND rl.origem = 'Landing' THEN 'Reprocessed Landing'
        WHEN l.origem = 'Reprocessado' AND rl.tipo = 'Afiliado' THEN 'Reprocessed Affiliate'
        WHEN l.origem = 'Reprocessado' THEN 'Reprocessed Others'
        ELSE fhlf.acquisition_channel
      END AS acquisition_channel_rep,
      rl.usuario_que_indicou_id AS origin_lead_usuario_que_indicou_id,
      COALESCE(
            COALESCE(rl.affiliate_type, l.affiliate_type) = 'B2BPartner'
            OR COALESCE(pa_b2b.id, b2b_prime_draft.id_lead) IS NOT NULL
            , false) AS is_b2b,
      COALESCE(rl.affiliate_type, l.affiliate_type) AS affiliate_type,
      COALESCE(rl.lead_agent_id, l.lead_agent_id) IS NOT NULL AS is_agent_referral,
      l.status AS lead_status,
      COALESCE(l.reason_detail, l.reason) AS lead_reason,
      l.cidade,
      pj.job_status AS photo_job_status,
      pj.photographer_problem_reason AS photo_job_reason,
      lbc.dt_opt_out_sale,
      CASE
         WHEN l.is_for_sale::INT::BOOLEAN AND l.is_for_rent::INT::BOOLEAN THEN 'Hybrid'
         WHEN l.is_for_rent::INT::BOOLEAN THEN 'Only Rent'
         WHEN l.is_for_sale::INT::BOOLEAN THEN 'Only Sale'
         ELSE 'Organic'
      END AS lead_context_origin,
      CASE
         WHEN lbc.status_rent IS NULL THEN 'Not Qualified Yet'
         WHEN lbc.status_rent = 'EDITING' THEN 'Editing'
         WHEN lbc.status_rent = 'OPTED_OUT' THEN 'Opted Out'
         ELSE 'Once Published'
      END AS listing_rent_status
    FROM public.fact_house_listing_flows fhlf
    LEFT JOIN public.lead l
      ON l.id = fhlf.lead_id
    LEFT JOIN public.vw_lead_reason AS lr
      ON l.reason = lr.reason_detail
    LEFT JOIN reproc_leads rl
      ON rl.id = fhlf.lead_id
    LEFT JOIN public.house h
      ON h.id = fhlf.imovel_id
    LEFT JOIN pa_b2b
      ON pa_b2b.user_id = h.usuario_id
    LEFT JOIN b2b_prime_draft
      ON b2b_prime_draft.id_lead = l.id
    LEFT JOIN public.house_listing hl
      ON hl.id_house = fhlf.imovel_id
      AND hl.version = 0
    LEFT JOIN lbc
      ON lbc.id_house = h.id
    LEFT JOIN public.lead_sales_company lsc
      ON lsc.id_lead = l.id
    LEFT JOIN public.usuario u 
      ON u.id = lbc.user_registrant_rent
    LEFT JOIN public.photo_job pj
      ON fhlf.photo_job_id = pj.id
    LEFT JOIN first_job
      ON first_job.imovel_id = h.id
    LEFT JOIN photo_job AS fpj
      ON first_job.id_job = fpj.id
    WHERE
      lbc.is_for_sale
      OR l.is_for_sale::INT::BOOLEAN
  )
  SELECT
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
    CASE
        WHEN (dt_first_listing IS NOT NULL) THEN 'Listed'
        WHEN (dt_opportunity IS NOT NULL AND dt_first_listing IS NULL) AND photo_job_status in ('FotosTiradas','Completado', 'NaoListado') THEN 'NotListedYet'
        WHEN (dt_opportunity IS NOT NULL AND dt_opt_out_sale >= dt_opportunity AND dt_first_listing IS NULL) AND photo_job_status in ('FotosTiradas','Completado', 'NaoListado') THEN 'OptedOut Opportunity'
        WHEN (dt_opportunity IS NOT NULL AND dt_first_listing IS NULL AND photo_job_status in ('Agendado','Iniciado','Novo')) THEN 'PhotoJobScheduled'
        WHEN (dt_opportunity IS NOT NULL AND dt_first_listing IS NULL AND photo_job_status = 'Cancelado') THEN COALESCE(photo_job_reason, 'CancelledPhotoJob')
        WHEN (dt_opportunity IS NOT NULL AND dt_first_listing IS NULL) THEN COALESCE(photo_job_reason, 'CancelledPhotoJob')
        WHEN (dt_opportunity IS NULL AND dt_qualified IS NOT NULL AND lead_status = 'Descartado') THEN 'DiscardedQualified'
        WHEN (dt_opportunity IS NULL AND dt_qualified IS NOT NULL AND lead_status = 'Convertido') THEN 'NoPhotoJob'
        WHEN (dt_opportunity IS NULL AND dt_qualified IS NOT NULL AND conversao_id IS NOT NULL) THEN 'NoPhotoJob'
        WHEN (dt_opportunity IS NULL AND dt_qualified IS NOT NULL AND dt_opt_out_sale >= dt_qualified) THEN 'OptedOut Qualified'
        WHEN (dt_opportunity IS NULL AND lead_reason = 'EmProspeccao') THEN 'OnHold'
        WHEN (dt_qualified IS NULL AND lead_status = 'Descartado') THEN 'DiscardedProspect'
        WHEN (dt_qualified IS NULL AND lead_status = 'Novo' AND cidade = 'Outra cidade') THEN 'NaoProcessadoArea'
        WHEN (dt_qualified IS NULL AND lead_status = 'Novo') THEN 'NaoProcessado'
        WHEN (flow = 'Lead Flow' AND dt_qualified IS NULL) THEN 'NaoProcessado'
        WHEN (lead_status = 'Convertido' AND conversao_id IS NULL) THEN 'BrokenLeadFlow'
        WHEN (flow = 'Lead Flow' AND dt_prospect IS NULL AND lead_status IS NULL) THEN 'DiscardedLead'
        WHEN (flow = 'Self-Service Flow' AND dt_prospect IS NOT NULL AND dt_qualified IS NULL) THEN 'TermsNotAccepted'
        WHEN (flow = 'Self-Service Flow' AND dt_qualified IS NOT NULL AND dt_opportunity IS NULL) THEN 'NoPhotoJob'
        WHEN (flow = 'Organic Flow' AND dt_prospect IS NOT NULL AND dt_qualified IS NULL) THEN 'UnfinishedForm'
        WHEN (flow = 'Organic Flow' AND dt_qualified IS NOT NULL AND dt_opportunity IS NULL) THEN 'NoPhotoJob'
        ELSE 'NotMapped'
    END AS funnel_step,
    ((DATE_PART('day', dt_prospect - dt_lead) * 1440 +
      DATE_PART('hour', dt_prospect - dt_lead) * 60 +
      DATE_PART('minute', dt_prospect - dt_lead)) / 60.)::NUMERIC(14,2) AS hours_lead_to_prospect,
    ((DATE_PART('day', dt_qualified - dt_prospect) * 1440 +
      DATE_PART('hour', dt_qualified - dt_prospect) * 60 +
      DATE_PART('minute', dt_qualified - dt_prospect)) / 60.)::NUMERIC(14,2) AS hours_prospect_to_qualified,
    ((DATE_PART('day', dt_first_contact - dt_lead) * 1440 +
      DATE_PART('hour', dt_first_contact - dt_lead) * 60 +
      DATE_PART('minute', dt_first_contact - dt_lead)) / 60.)::NUMERIC(14,2) AS hours_lead_to_first_contact,
    ((DATE_PART('day', dt_first_contact - dt_prospect) * 1440 +
      DATE_PART('hour', dt_first_contact - dt_prospect) * 60 +
      DATE_PART('minute', dt_first_contact - dt_prospect)) / 60.)::NUMERIC(14,2) AS hours_prospect_to_first_contact,
    ((DATE_PART('day', dt_opportunity - dt_qualified) * 1440 +
      DATE_PART('hour', dt_opportunity - dt_qualified) * 60 +
      DATE_PART('minute', dt_opportunity - dt_qualified)) / 60.)::NUMERIC(14,2) AS hours_qualified_to_opportunity,
    ((DATE_PART('day', dt_first_listing - dt_opportunity) * 1440 +
      DATE_PART('hour', dt_first_listing - dt_opportunity) * 60 +
      DATE_PART('minute', dt_first_listing - dt_opportunity)) / 60.)::NUMERIC(14,2) AS hours_opportunity_to_listing,
    ((DATE_PART('day', dt_first_listing - dt_lead) * 1440 +
      DATE_PART('hour', dt_first_listing - dt_lead) * 60 +
      DATE_PART('minute', dt_first_listing - dt_lead)) / 60.)::NUMERIC(14,2) AS hours_lead_to_listing,
    ((DATE_PART('day', dt_prospect - dt_lead) * 1440 +
      DATE_PART('hour', dt_prospect - dt_lead) * 60 +
      DATE_PART('minute', dt_prospect - dt_lead)) / 1440.)::NUMERIC(14,2) AS days_lead_to_prospect,    
    ((DATE_PART('day', dt_qualified - dt_prospect) * 1440 +
      DATE_PART('hour', dt_qualified - dt_prospect) * 60 +
      DATE_PART('minute', dt_qualified - dt_prospect)) / 1440.)::NUMERIC(14,2) AS days_prospect_to_qualified,
    ((DATE_PART('day', dt_first_contact - dt_lead) * 1440 +
      DATE_PART('hour', dt_first_contact - dt_lead) * 60 +
      DATE_PART('minute', dt_first_contact - dt_lead)) / 1440.)::NUMERIC(14,2) AS days_lead_to_first_contact,
    ((DATE_PART('day', dt_first_contact - dt_prospect) * 1440 +
      DATE_PART('hour', dt_first_contact - dt_prospect) * 60 +
      DATE_PART('minute', dt_first_contact - dt_prospect)) / 1440.)::NUMERIC(14,2) AS days_prospect_to_first_contact,
    ((DATE_PART('day', dt_opportunity - dt_qualified) * 1440 +
      DATE_PART('hour', dt_opportunity - dt_qualified) * 60 +
      DATE_PART('minute', dt_opportunity - dt_qualified)) / 1440.)::NUMERIC(14,2) AS days_qualified_to_opportunity,
    ((DATE_PART('day', dt_first_listing - dt_opportunity) * 1440 +
      DATE_PART('hour', dt_first_listing - dt_opportunity) * 60 +
      DATE_PART('minute', dt_first_listing - dt_opportunity)) / 1440.)::NUMERIC(14,2) AS days_opportunity_to_listing,
    ((DATE_PART('day', dt_first_listing - dt_lead) * 1440 +
      DATE_PART('hour', dt_first_listing - dt_lead) * 60 +
      DATE_PART('minute', dt_first_listing - dt_lead)) / 1440.)::NUMERIC(14,2) AS days_lead_to_listing,
    CASE
      WHEN (dt_conversion IS NULL AND dt_discarded IS NULL) THEN NULL 
      ELSE
        ((DATE_PART('day', LEAST(COALESCE(dt_conversion, dt_discarded + INTERVAL '1 DAY'), 
            COALESCE(dt_discarded, dt_conversion + INTERVAL '1 DAY')) - dt_lead) * 1440 +
        DATE_PART('hour', LEAST(COALESCE(dt_conversion, dt_discarded + INTERVAL '1 DAY'), 
            COALESCE(dt_discarded, dt_conversion + INTERVAL '1 DAY')) - dt_lead) * 60 +
        DATE_PART('minute', LEAST(COALESCE(dt_conversion, dt_discarded + INTERVAL '1 DAY'), 
            COALESCE(dt_discarded, dt_conversion + INTERVAL '1 DAY')) - dt_lead)) / 1440.)::NUMERIC(14,2)
    END AS days_lead_to_processing,
    acquisition_channels.acquisition_channel_rep,
    acquisition_channels.origin_lead_usuario_que_indicou_id,
    acquisition_channels.acquisition_channel_rep !~~ 'Reprocessed%' AS is_not_reprocessed,
    acquisition_channels.is_b2b,
    acquisition_channels.affiliate_type,
    acquisition_channels.is_agent_referral,
    acquisition_channels.dt_opt_out_sale,
    acquisition_channels.lead_context_origin,
    acquisition_channels.listing_rent_status
  FROM acquisition_channels
