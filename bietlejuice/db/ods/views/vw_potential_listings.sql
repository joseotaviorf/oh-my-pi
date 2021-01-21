--drop view if exists vw_potential_listings;
--create or replace view vw_potential_listings as
-- first conversion task created for a lead
with base_lead_tasks_first AS (
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
leads_b2b AS (
  SELECT DISTINCT
    l.id AS id_lead,
    pa_b2b_online.partner_id AS online_partner_id
  FROM lead AS l
  JOIN partner_agent AS pa_b2b_online
    ON pa_b2b_online.user_id = l.usuario_que_indicou_id
  WHERE pa_b2b_online.partner_id IS NOT NULL
),
autonomous_agent_info AS (
SELECT
	pa.user_id AS sk_autonomous_agent,
	pa.ts_created
FROM partner_agent AS pa
JOIN partner AS dp
	ON pa.partner_id = dp.id
	AND dp.type = 'AUTONOMOUS_AGENT'
	AND dp.id <> '257' -- Test User
)
SELECT
    f.id AS sk_house_listing_flow,
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
    COALESCE(aa_info.sk_autonomous_agent, -1) AS sk_autonomous_agent,
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
    COALESCE(aa_info.sk_autonomous_agent IS NOT NULL, FALSE) AS is_autonomous_agent,
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
  LEFT JOIN autonomous_agent_info AS aa_info
    ON aa_info.sk_autonomous_agent = h.usuario_que_cadastrou_id
    AND h.data_criacao >= aa_info.ts_created --This rule might change when we start to considering migration
    AND h.external_id IS NOT NULL --This rule might change when we start to considering migration
