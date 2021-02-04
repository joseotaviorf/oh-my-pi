--drop view if exists vw_potential_listings;
--create or replace view vw_potential_listings as
SELECT
    f.id AS sk_house_listing_flow,
    plhb.sk_condo,
    COALESCE(f.lead_id, '-1'::INTEGER) AS sk_lead,
    COALESCE(f.conversao_id, '-1'::INTEGER) AS sk_lead_conversion,
    COALESCE(f.photo_job_id, '-1'::INTEGER) AS sk_first_photo_job,
    plhb.sk_house_listing,
    COALESCE(f.rep_id, '-1'::INTEGER) AS sk_user_house_registrant,
    pllt.sk_user_sales_rep,
    COALESCE(f.affiliate_id, f.origin_lead_usuario_que_indicou_id::INTEGER, '-1'::INTEGER) AS sk_user_lead_affiliate,
    pllt.sk_user_first_task_assignee,
    pllt.sk_user_last_task_assignee,
    COALESCE(f.region_id, '-1'::INTEGER) AS sk_region,
    COALESCE(dr.city_id, '-1'::INTEGER) AS id_city,
    plhb.sk_partner,
    plhb.sk_autonomous_agent,
    COALESCE(TO_CHAR(f.dt_lead::DATE::TIMESTAMP WITH TIME ZONE, 'YYYYMMDD')::INTEGER, '-1'::INTEGER) AS sk_lead_date,
    COALESCE(TO_CHAR(f.dt_prospect::DATE::TIMESTAMP WITH TIME ZONE, 'YYYYMMDD')::INTEGER, '-1'::INTEGER) AS sk_prospect_date,
    pllt.sk_first_task_created_date,
    pllt.sk_first_task_closed_date,
    pllt.sk_last_task_created_date,
    pllt.sk_last_task_closed_date,
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
    plhb.is_exclusive,
    pllt.first_isales_intervention,
    plrl.lead_type,
    plrl.lead_origin,
    CASE WHEN lfet.id_lead IS NOT NULL THEN lfet.tracking_source ELSE plrl.utm_source END AS utm_source,
    CASE WHEN lfet.id_lead IS NOT NULL THEN lfet.tracking_medium ELSE plrl.utm_medium END AS utm_medium,
    lfet.tracking_platform,
    COALESCE(LOWER(BTRIM(lfet.tracking_campaign)) ~* '(institucional)|(branded)' AND LOWER(BTRIM(lfet.tracking_campaign)) !~* '(non-branded)',
             plrl.branded_lead) AS is_branded,
    f.is_b2b,
    plhb.is_autonomous_agent,
    plrl.reprocessed_flg,
    a.is_doorman,
    f.acquisition_channel_rep = 'Inside Sales' AS is_isales_direct_register,
    f.acquisition_channel_rep = 'Admin' AS is_cx_direct_register,
    (f.acquisition_channel_rep = 'Inside Sales') OR (f.acquisition_channel_rep = 'Admin') AS is_ops_direct_register,
    pllt.has_isales_intervention,
    pllt.has_fup_photo_task,
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
    plhb.house_usuario_que_cadastrou_id,
    f.dt_opt_out_rent AS ts_opted_out_rent,
    f.lead_context_origin,
    f.listing_sale_status
  FROM listing_flows_with_reprocessed_leads f
  LEFT JOIN lead_first_event_tracking lfet
    ON lfet.id_lead = f.lead_id
  LEFT JOIN acquisitions a
    ON a.id = f.id
  LEFT JOIN potential_listings_lead_tasks pllt
    ON pllt.id = f.id
  LEFT JOIN potential_listings_rep_leads plrl
    ON plrl.id = f.id
  LEFT JOIN staging.dim_region dr
    ON dr.sk_region = f.region_id
  LEFT JOIN potential_listings_house_b2b plhb
  	ON plhb.id = f.id
