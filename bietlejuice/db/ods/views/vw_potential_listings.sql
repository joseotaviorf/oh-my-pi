--drop view if exists vw_potential_listings;
--create or replace view vw_potential_listings as
WITH legacy_doorman AS (
  SELECT
    porteiros_legado."Status" AS status,
    892700000 + porteiros_legado."Cod Imóvel"::double precision::BIGINT AS imovel_id
  FROM gsheets.porteiros_legado
  WHERE (porteiros_legado."Status" IN ('Listing', 'Alugado', 'Foto', 'Foto com problema', 'Lead'))
    AND porteiros_legado."Cod Imóvel" IS NOT NULL
),
rn_lead AS (
    SELECT lead_tasks.rep_id,
        lead_tasks.lead_id,
        lead_tasks.dt_created,
        lead_tasks.dt_closed,
        ROW_NUMBER() OVER (PARTITION BY lead_tasks.lead_id ORDER BY lead_tasks.dt_created ASC) AS rn_first,
        ROW_NUMBER() OVER (PARTITION BY lead_tasks.lead_id ORDER BY lead_tasks.dt_created DESC) AS rn_last
    FROM crm.lead_tasks
),
-- first conversion task created for a lead
base_lead_tasks_first AS (
    SELECT
        rn_lead.rep_id,
        rn_lead.lead_id,
        rn_lead.dt_created,
        rn_lead.dt_closed
    FROM rn_lead
    WHERE rn_first = 1
),
-- last conversion task created for a lead
base_lead_tasks_last AS (
  SELECT
      rn_lead.rep_id,
      rn_lead.lead_id,
      rn_lead.dt_created,
      rn_lead.dt_closed
  FROM rn_lead
  WHERE rn_last = 1
),
base_photo_tasks AS (
  SELECT distinct
    COALESCE(h.id, h_direct.id)::INTEGER AS house_id,
    MAX((task_type = 'AgendarJobDeFotografo')::INTEGER)::BOOLEAN AS has_job_photo,
    MAX((task_type = 'FupFoto')::INTEGER)::BOOLEAN AS has_fup_photo
  FROM crm.photo_tasks AS pt
  LEFT JOIN photo_job AS pj
    ON pt.origin_id = pj.id
  LEFT JOIN house AS h
    ON h.id = pj.imovel_id
  LEFT JOIN house AS h_direct
    ON h_direct.id = pt.origin_id
  WHERE COALESCE(h.id, h_direct.id) IS NOT NULL
  GROUP BY 1
),
base_leads AS (
  SELECT
    lead.id AS lead_id,
    lead.tipo AS lead_type,
    lead.origem AS lead_origin,
    lead.utm_source,
    lead.utm_medium,
    COALESCE(LOWER(BTRIM(lead.utm_campaign)) ~* '(institucional)|(branded)' AND LOWER(BTRIM(lead.utm_campaign)) !~* '(non-branded)', false) AS branded_lead,
    lead.codigo_imobiliaria IS NOT NULL OR lead.flg_b2b AS b2b_lead
    FROM lead
),
base_leads_reproc AS (
  SELECT
    lead.id AS lead_id,
    lead.tipo AS lead_type,
    lead.origem AS lead_origin,
    lead.utm_source,
    lead.utm_medium,
    COALESCE(LOWER(BTRIM(lead.utm_campaign)) ~* '(institucional)|(branded)' AND LOWER(BTRIM(lead.utm_campaign)) !~* '(non-branded)', false) AS branded_lead,
    lead.codigo_imobiliaria IS NOT NULL OR lead.flg_b2b AS b2b_lead,
    rl.id_origin_lead AS old_lead_id
    FROM lead
    JOIN reprocessed_lead AS rl
      ON rl.id = lead.id
    WHERE lead.origem = 'Reprocessado'
),
rep_leads AS (
  SELECT bl.lead_id,
    COALESCE(old_bl.lead_type, bl.lead_type) AS lead_type,
    COALESCE(old_bl.lead_origin, bl.lead_origin) AS lead_origin,
    COALESCE(old_bl.utm_source, bl.utm_source) AS utm_source,
    COALESCE(old_bl.utm_medium, bl.utm_medium) AS utm_medium,
    COALESCE(old_bl.branded_lead, bl.branded_lead) AS branded_lead,
    COALESCE(old_bl.b2b_lead, bl.b2b_lead) AS b2b_lead,
    COALESCE(bl.lead_origin = 'Reprocessado', false) AS reprocessed_flg
    FROM base_leads AS bl
    LEFT JOIN base_leads_reproc AS old_bl
      ON old_bl.old_lead_id = bl.lead_id
    GROUP BY 1,2,3,4,5,6,7,8
),
acquisitions AS (
  SELECT
    f.id,
    CASE
      WHEN d.imovel_id IS NOT NULL AND f.is_not_reprocessed THEN 'Lead Flow'
      ELSE f.flow
    END AS flow,
    CASE
      WHEN d.imovel_id IS NOT NULL AND f.is_not_reprocessed THEN 'Non-Self Service'
      ELSE f.acquisition_method
    END AS acquisition_method,
    CASE
      WHEN d.imovel_id IS NOT NULL AND f.is_not_reprocessed THEN 'Doorman'
      ELSE f.acquisition_channel_rep
    END AS acquisition_channel,
    CASE
      WHEN d.imovel_id IS NOT NULL AND f.is_not_reprocessed THEN 'Doorman'
      ELSE f.acquisition_source
    END AS acquisition_source,
    CASE
      WHEN d.imovel_id IS NOT NULL AND f.is_not_reprocessed THEN true
      ELSE f.acquisition_source = 'Doorman'
    END AS is_doorman
  FROM listing_flows_with_reprocessed_leads AS f
  LEFT JOIN legacy_doorman AS d
    ON f.imovel_id = d.imovel_id
),
leads_b2b AS (
  SELECT DISTINCT
    l.id AS id_lead,
    pa_b2b_online.partner_id AS online_partner_id
  FROM lead AS l
  LEFT JOIN partner_agent AS pa_b2b_online
    ON pa_b2b_online.user_id = l.usuario_que_indicou_id
  WHERE pa_b2b_online.partner_id IS NOT NULL
)
    SELECT f.id AS sk_house_listing_flow,
    COALESCE(h.condo_id, '-1'::INTEGER::BIGINT) AS sk_condo,
    COALESCE(f.lead_id, '-1'::INTEGER) AS sk_lead,
    COALESCE(f.conversao_id, '-1'::INTEGER) AS sk_lead_conversion,
    COALESCE(f.photo_job_id, '-1'::INTEGER) AS sk_first_photo_job,
    COALESCE(f.imovel_id || '00' || COALESCE(hl_version_zero.version, 1)::VARCHAR, '-1')::BIGINT AS sk_house_listing,
    COALESCE(f.rep_id, '-1'::INTEGER) AS sk_user_house_registrant,
    COALESCE(f.rep_id, btl.rep_id, '-1'::INTEGER) AS sk_user_sales_rep,
    COALESCE(f.affiliate_id, f.origin_lead_usuario_que_indicou_id::INTEGER, '-1'::INTEGER) AS sk_user_lead_affiliate,
    COALESCE(btf.rep_id, '-1'::INTEGER) AS sk_user_first_task_assignee,
    COALESCE(btl.rep_id, '-1'::INTEGER) AS sk_user_last_task_assignee,
    COALESCE(f.region_id, '-1'::INTEGER) AS sk_region,
    COALESCE(dr.city_id, '-1'::INTEGER) AS id_city,
    COALESCE(pa_b2b_prime.partner_id, l_b2b.online_partner_id, f.partner_id, '-1'::INTEGER::BIGINT) AS sk_partner,
    COALESCE(TO_CHAR(f.dt_lead::DATE::TIMESTAMP WITH TIME ZONE, 'YYYYMMDD')::INTEGER, '-1'::INTEGER) AS sk_lead_date,
    COALESCE(TO_CHAR(f.dt_prospect::DATE::TIMESTAMP WITH TIME ZONE, 'YYYYMMDD')::INTEGER, '-1'::INTEGER) AS sk_prospect_date,
    COALESCE(TO_CHAR(CASE 
                                    WHEN btf.dt_created < f.dt_lead THEN f.dt_lead 
                                    ELSE btf.dt_created 
                                END::DATE::TIMESTAMP WITH TIME ZONE, 'YYYYMMDD')::INTEGER, '-1'::INTEGER
     ) AS sk_first_task_created_date,
    COALESCE(TO_CHAR(CASE 
                                    WHEN btf.dt_closed < f.dt_lead THEN f.dt_lead 
                                    ELSE btf.dt_closed 
                                END::DATE::TIMESTAMP WITH TIME ZONE, 'YYYYMMDD')::INTEGER, '-1'::INTEGER
     ) AS sk_first_task_closed_date,
    COALESCE(TO_CHAR(CASE 
                                    WHEN btl.dt_created < f.dt_lead THEN f.dt_lead 
                                    ELSE btl.dt_created 
                                END::DATE::TIMESTAMP WITH TIME ZONE, 'YYYYMMDD')::INTEGER, '-1'::INTEGER
     ) AS sk_last_task_created_date,
    COALESCE(TO_CHAR(CASE 
                                    WHEN btl.dt_closed < f.dt_lead THEN f.dt_lead 
                                    ELSE btl.dt_closed 
                                END::DATE::TIMESTAMP WITH TIME ZONE, 'YYYYMMDD')::INTEGER, '-1'::INTEGER
     ) AS sk_last_task_closed_date,
    COALESCE(TO_CHAR(f.dt_first_contact::DATE::TIMESTAMP WITH TIME ZONE, 'YYYYMMDD')::INTEGER, '-1'::INTEGER) AS sk_first_contact_date,
    COALESCE(TO_CHAR(f.dt_conversion::DATE::TIMESTAMP WITH TIME ZONE, 'YYYYMMDD')::INTEGER, '-1'::INTEGER) AS sk_conversion_date,
    COALESCE(TO_CHAR(f.dt_qualified::DATE::TIMESTAMP WITH TIME ZONE, 'YYYYMMDD')::INTEGER, '-1'::INTEGER) AS sk_qualified_date,
    COALESCE(TO_CHAR(f.dt_opportunity::DATE::TIMESTAMP WITH TIME ZONE, 'YYYYMMDD')::INTEGER, '-1'::INTEGER) AS sk_opportunity_date,
    COALESCE(TO_CHAR(f.dt_first_listing::DATE::TIMESTAMP WITH TIME ZONE, 'YYYYMMDD')::INTEGER, '-1'::INTEGER) AS sk_first_listing_date,
    COALESCE(TO_CHAR(f.dt_discarded::DATE::TIMESTAMP WITH TIME ZONE, 'YYYYMMDD')::INTEGER, '-1'::INTEGER) AS sk_discard_date,
    COALESCE(TO_CHAR(f.ts_sales_company_sent, 'YYYYMMDD')::INTEGER, '-1'::INTEGER) AS sk_sales_company_lead_sent_date,
    COALESCE(f.user_id_lead_first_discarder, '-1'::INTEGER) AS sk_user_lead_first_discarder,
    COALESCE(f.user_id_lead_last_discarder, '-1'::INTEGER) AS sk_user_lead_last_discarder,
    a.flow,
    a.acquisition_method,
    a.acquisition_channel,
    a.acquisition_source,
    CASE
      WHEN f.dt_first_listing IS NOT NULL THEN 'listing'
      WHEN f.dt_opportunity IS NOT NULL THEN 'opportunity'
      WHEN f.dt_qualified IS NOT NULL THEN 'qualified'
      WHEN f.dt_first_contact IS NOT NULL THEN 'first contact'
      WHEN f.dt_prospect IS NOT NULL THEN 'prospect'
      WHEN f.dt_lead IS NOT NULL THEN 'lead'
      ELSE NULL
    END AS funnel_step,
    f.funnel_step AS funnel_drop_reason,
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
    h.exclusivity AS is_exclusive,
    CASE
      WHEN btf.rep_id IS NOT NULL THEN 'Lead'
      WHEN COALESCE(bpt.house_id, f.rep_id) IS NOT NULL THEN 'Photojob'
      ELSE NULL
    END AS first_isales_intervention,
    bl.lead_type,
    bl.lead_origin,
    CASE WHEN lfet.id_lead IS NOT NULL THEN lfet.tracking_source ELSE bl.utm_source END AS utm_source,
    CASE WHEN lfet.id_lead IS NOT NULL THEN lfet.tracking_medium ELSE bl.utm_medium END AS utm_medium,
    lfet.tracking_platform,
    COALESCE(LOWER(BTRIM(lfet.tracking_campaign)) ~* '(institucional)|(branded)' AND LOWER(BTRIM(lfet.tracking_campaign)) !~* '(non-branded)',
             bl.branded_lead) AS is_branded,
    f.is_b2b,
    bl.reprocessed_flg,
    a.is_doorman,
    f.acquisition_channel_rep = 'Inside Sales' AS is_isales_direct_register,
    f.acquisition_channel_rep = 'Admin' AS is_cx_direct_register,
    (f.acquisition_channel_rep = 'Inside Sales') OR (f.acquisition_channel_rep = 'Admin') AS is_ops_direct_register,
    COALESCE(f.isales_registrant_id, btf.rep_id) IS NOT NULL
    OR (bpt.has_job_photo = TRUE AND NOT f.is_self_service_photo_job_scheduled)
        AS has_isales_intervention,
    bpt.has_fup_photo AS has_fup_photo_task,
    lfet.tracking_referring_domain AS lead_referring_domain,
    CASE
      WHEN LOWER(lfet.tracking_referring_domain) LIKE '%corretor%' THEN 'Agents'
      WHEN LOWER(lfet.tracking_referring_domain) LIKE '%indicaai%' THEN 'Indica Ai'
      WHEN LOWER(lfet.tracking_referring_domain) LIKE '%proprietario%' THEN 'Owner'
      ELSE 'Other'
    END AS lead_referring_category,
    f.lead_id,
    f.affiliate_type AS listing_flows_affiliate_type,
    COALESCE(f.affiliate_id, f.origin_lead_usuario_que_indicou_id::INTEGER, '-1'::INTEGER) AS affiliate_id,
    f.is_agent_referral,
    COALESCE(f.region_id, -1) AS region_id,
    h.usuario_que_cadastrou_id AS house_usuario_que_cadastrou_id,
    f.dt_opt_out_rent AS ts_opted_out_rent,
    f.lead_context_origin,
    f.listing_sale_status
  FROM listing_flows_with_reprocessed_leads AS f
  LEFT JOIN lead_first_event_tracking AS lfet
    ON lfet.id_lead = f.lead_id
  LEFT JOIN acquisitions AS a
    ON a.id = f.id
  LEFT JOIN base_lead_tasks_first AS btf
    ON btf.lead_id = f.lead_id
  LEFT JOIN base_lead_tasks_last AS btl
    ON btl.lead_id = f.lead_id
  LEFT JOIN base_photo_tasks AS bpt
    ON f.imovel_id = bpt.house_id
  LEFT JOIN rep_leads AS bl
    ON bl.lead_id = f.lead_id
  LEFT JOIN house AS h
    ON f.imovel_id = h.id
  LEFT JOIN staging.dim_region AS dr
    ON dr.sk_region = f.region_id
  LEFT JOIN leads_b2b AS l_b2b
    ON l_b2b.id_lead = f.lead_id
  LEFT JOIN partner_agent AS pa_b2b_prime
    ON h.usuario_id = pa_b2b_prime.user_id
  LEFT JOIN house_listing AS hl_version_zero
    ON hl_version_zero.id_house = f.imovel_id
      AND hl_version_zero.version = 0

