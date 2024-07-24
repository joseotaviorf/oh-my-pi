WITH stg_fact_supply AS (
  SELECT
    MD5(CONCAT_WS('#', COALESCE(sk_supply_lead, -1), COALESCE(id_house, -1))) AS sk_supply,
    business_context AS nm_business_context,
    supply_source AS nm_supply_source,
    sk_supply_lead,
    id_lead_ebdb AS sk_lead,
    id_region AS sk_region,
    id_house AS sk_house,
    id_user_registrant AS sk_user_registrant,
    id_user_conversion AS sk_user_conversion,
    IF(supply_source = '3P', id_lead, -1) AS sk_lead_3p,
    CONCAT_WS('#',LOWER(funnel_step), business_event) AS bk_funnel_step,
    CONCAT_WS('#',LOWER(funnel_step), LOWER(drop_step_reason)) AS bk_discard,
    CONCAT_WS('#',
      LEFT(COALESCE(ops_objective,'non') ,3),
      LEFT(REGEXP_REPLACE(COALESCE(ops_agent,'non'), 'is_',''), 3),
      LEFT(COALESCE(ops_partner, 'non'), 3),
      LEFT(COALESCE(ops_contact_medium, 'non'), 3),
      LEFT(COALESCE(ops_approach, 'non'), 3),
      LEFT(COALESCE(ops_assigned, 'non'), 3)
    ) AS bk_ops,
    CONCAT_WS(
      '#',
      reprocessed,
      reprocessing_entity_type,
      reprocessing_table_name
    ) AS bk_recovery,
    CONCAT_WS(
      '#',
      COALESCE(application, 'not_mapped'),
      'n/a',
      'n/a'
    ) AS bk_conversion_path,
    CONCAT_WS(
      '#',
      COALESCE(lead_application, 'not_mapped'),
      COALESCE(platform, 'not_mapped'),
      'n/a'
    ) AS bk_acquisition_path,
    id_referred_by AS sk_user_affiliate, 
    CONCAT_WS(
      '#',
      sk_supply_lead, 
      COALESCE(supply_source, 'non'), 
      business_context
    ) AS bk_acq_lead,
    date_format(ts_event_adjusted, 'yyyyMMdd') AS sk_date,
    MIN(ts_event_adjusted) OVER (
      PARTITION BY 
        ses.id_lead,
        ses.id_lead_ebdb,
        ses.business_context,
        ses.id_house,
        ses.supply_source
      RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS ts_first_event_date,
    ts_event_original,
    ts_event_adjusted AS ts_event,
    supply_source,
    ses.medium AS utm_medium,
    ses.source AS utm_source,
    ses.campaign AS utm_campaign,
    ses.term AS utm_term,
    ses.content AS utm_content,
    CASE
      WHEN 
        NULLIF(CONCAT_WS('.', SLICE(SPLIT(tef.correct_utm_campaign, '[.]'), 2, 7)), '') IS NOT NULL 
        THEN 'sufix_from_exception_flow'
      WHEN 
        dic.naming_convention_sufix IS NOT NULL 
        THEN 'sufix_from_dictionary'
      WHEN 
        NULLIF(CONCAT_WS('.', SLICE(SPLIT(ses.campaign, '[.]'), 2, 7)), '') IS NOT NULL 
        THEN 'sufix_from_campaign'
      ELSE 
        'not_mapped'
    END AS tp_flow_media_setup,
    COALESCE(
      NULLIF(CONCAT_WS('.', SLICE(SPLIT(tef.correct_utm_campaign, '[.]'), 2, 7)), ''), -- sufix_from_exception_flow
      dic.naming_convention_sufix, -- sufix_from_dictionary,
      NULLIF(CONCAT_WS('.', SLICE(SPLIT(ses.campaign, '[.]'), 2, 7)), '') -- sufix_from_campaign
    )  AS sufix_from_naming_convention
  FROM 
    datalake_supply_flows.supply_events_tracking AS ses
  LEFT JOIN 
    datalake_gsheets_clean.taxonomy_demand_exception_flow AS tef
      ON (LOWER(ses.medium) = LOWER(tef.utm_medium))
        AND (LOWER(ses.source) = LOWER(tef.utm_source))
        AND (LOWER(ses.campaign) = LOWER(tef.utm_campaign))
  LEFT JOIN 
    datalake_growth_taxonomy.unified_taxonomy_dictionary AS dic
      ON (LOWER(ses.medium) = LOWER(dic.utm_medium))
        AND (LOWER(ses.source) = LOWER(dic.utm_source))
        AND (LOWER(ses.campaign) = LOWER(dic.utm_campaign))
)

SELECT 
  sfs.sk_supply, 
  sfs.nm_business_context,
  sfs.nm_supply_source,
  COALESCE(sfs.sk_supply_lead, -1) AS sk_supply_lead,
  COALESCE(sfs.sk_lead, -1) AS sk_lead,
  COALESCE(sfs.sk_lead_3p, -1) AS sk_lead_3p,
  COALESCE(sfs.sk_house, -1) AS sk_house,
  COALESCE(sfs.sk_region, -1) AS sk_region,
  COALESCE(sfs.sk_user_registrant, -1) AS sk_user_registrant,
  COALESCE(sfs.sk_user_conversion, -1) AS sk_user_conversion,
  COALESCE(dfs.sk_funnel_step, -1) AS sk_funnel_step,
  COALESCE(sof.sk_ops, -1) AS sk_ops,
  COALESCE(dsd.sk_discard, -1) AS sk_discard,
  COALESCE(sfs.sk_user_affiliate, -1) AS sk_user_affiliate,
  COALESCE(dal.sk_acquisition_lead, -1) AS sk_acquisition_lead,
  COALESCE(srf.sk_recovery, -1) AS sk_recovery,
  COALESCE(upa.sk_user_path, -1) AS sk_acquisition_user_path,
  COALESCE(upc.sk_user_path, upa.sk_user_path) AS sk_conversion_user_path,
  COALESCE(ms.id_media_setup, '-1') AS sk_media_setup,
  COALESCE(h.id_user, -1) AS sk_owner,
  COALESCE(sfs.sufix_from_naming_convention, '-1') AS nm_media_setup,
  COALESCE(sfs.tp_flow_media_setup, '-1') AS tp_flow_media_setup,
  sfs.utm_medium,
  sfs.utm_source,
  sfs.utm_campaign,
  sfs.utm_term,
  sfs.utm_content,
  sfs.sk_date,
  sfs.ts_first_event_date,
  sfs.ts_event_original,
  sfs.ts_event,
  NOW() AS ts_load
FROM 
  stg_fact_supply AS sfs
LEFT JOIN 
  dw_growth.dim_funnel_step AS dfs
    USING (bk_funnel_step)
LEFT JOIN 
  dw_growth.dim_supply_operation_flow AS sof
    USING (bk_ops)
LEFT JOIN 
  dw_growth.dim_supply_discards AS dsd
    USING (bk_discard)
LEFT JOIN
  dw_growth.dim_acquisition_lead AS dal
    USING (bk_acq_lead)
LEFT JOIN 
  dw_growth.dim_supply_recovery_flow AS srf
    USING (bk_recovery)
LEFT JOIN 
  dw_growth.dim_supply_user_path AS upa
    ON (sfs.bk_acquisition_path = upa.bk_user_path)
      AND (upa.id_level = 1)
LEFT JOIN 
  dw_growth.dim_supply_user_path AS upc
    ON (sfs.bk_conversion_path = upc.bk_user_path)
LEFT JOIN 
  datalake_ebdb_listing.house AS h
    ON (sfs.sk_house = h.id)
LEFT JOIN 
  datalake_growth_taxonomy.media_setup AS ms
    ON (LOWER(sfs.sufix_from_naming_convention) = LOWER(ms.naming_convention_sufix))