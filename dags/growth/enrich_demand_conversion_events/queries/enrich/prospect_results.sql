WITH business_model AS (
  SELECT DISTINCT
    V.code AS visit_code,
    VBM.business_model AS business_model,
    VBM.business_model IN ('BM_3P_LEAD_GEN_3P_SUPPLY', 'BM_3P_LEAD_GEN_1P_SUPPLY') AS is_cqa_demand,
    VBM.business_model IN ('BM_1P', 'BM_3P_SUPPLY_1P_DEMAND_AGENT') AS is_1p_demand,
    VBM.is_3p_demand
  FROM
    datalake_visit.visits AS V
  INNER JOIN
    datalake_visit.visit_business_model AS VBM
      ON V.id_visit = VBM.id_visit
),
company_relation as (
    SELECT DISTINCT
        COALESCE(u.id, -1) AS sk_user,
        bc.type AS buyer_company_relation_type,
        bc.ts_started AS ts_start,
        IFNULL(bc.ts_finished,current_date()) AS ts_end
    FROM
        datalake_rede_platform_clean.buyer_company AS bc
    LEFT JOIN
        datalake_ebdb_clean.user AS u
            ON bc.uuid_person = u.uuid_person
),
adhoc_rules AS (
  SELECT
    dpce.id_demand_prospect_conversion_event,
    dpce.id_prospect,
    dpce.business_context,
    dpce.sale_type,
    dpce.id_event_type,
    dpce.event_name,
    CASE
      WHEN dpce.product_origin = 'AGENT_PWA'
        AND dpce.id_agent = sef.id_agent
        AND (bcr.buyer_company_relation_type IS NULL OR bcr.buyer_company_relation_type != '3P')
      THEN "sale.acq.nonorg.na.d.referral.tqc1p"
      WHEN dpce.utm_medium = 'TQC 1P'
      THEN "sale.acq.nonorg.na.d.referral.tqc1p"
      WHEN dpce.utm_medium = 'TQC 3P'
        OR (dpce.product_origin = 'AGENT_PWA'
          AND bm.is_3p_demand = TRUE)
      THEN "sale.acq.nonorg.na.d.referral.tqc3p"
      WHEN dpce.product_origin = 'AGENT_PWA'
      THEN "hybr.acq.nonorg.na.d.referral.agents"
      WHEN dpce.utm_medium = 'plaquinhas_ada_whatsapp'
      THEN "hybr.acq.nonorg.na.d.placas.na"
      WHEN utm_campaign IS NULL
        AND utm_source IS NULL
        AND utm_medium IS NULL
        AND app_type IS NULL
      THEN "lost.los.lostra.lostra.l.losttracking.losttracking"
      WHEN utm_campaign IS NULL
        AND utm_source IS NULL
        AND utm_medium IS NULL
        AND app_type IS NOT NULL
      THEN "na.acq.org.na.d.direct.na"
    END AS utm_adhoc_rule,
    dpce.id_rent_flow,
    dpce.id_sale_flow,
    dpce.id_booking,
    dpce.id_visit,
    dpce.id_offer,
    dpce.id_talk_to_agent,
    dpce.id_house,
    dpce.id_region,
    dpce.id_owner,
    dpce.id_agent,
    CASE
      WHEN dpce.utm_medium = 'plaquinhas_ada_whatsapp'
        AND dpce.utm_campaign = 'offline_table'
      THEN "hybr.acq.nonorg.na.d.placas.na.ada_whatsapp"
      ELSE dpce.utm_campaign
    END AS utm_campaign,
    dpce.utm_medium,
    dpce.utm_source,
    dpce.utm_term,
    dpce.utm_content,
    dpce.entrance_uri,
    dpce.app_type,
    dpce.booking_creator,
    dpce.product_origin,
    bm.is_3p_demand,
    bm.is_1p_demand,
    bm.is_cqa_demand,
    CASE
      WHEN dpce.product_origin IN ('CONVERSATIONAL - WHATSAPP_CONCIERGE', 'CONVERSATIONAL - NATIVE_CONCIERGE')
      THEN "Concierge"
      WHEN dpce.booking_creator IS NULL
        AND dpce.id_booking IS NOT NULL
      THEN "Lost Tracking"
      WHEN dpce.booking_creator IS NULL
        AND dpce.id_booking IS NULL
      THEN "SelfService"
      WHEN dpce.booking_creator = 'SelfService'
      THEN 'SelfService'
      WHEN dpce.booking_creator = 'Secretaria'
      THEN 'Secretaria'
      WHEN dpce.booking_creator = 'Admin/CX'
      THEN 'CX'
      WHEN dpce.product_origin = 'AGENT_PWA'
        AND dpce.id_agent = sef.id_agent
      THEN 'Agent'
      WHEN dpce.product_origin = 'AGENT_PWA'
        AND bm.is_3p_demand = TRUE
      THEN 'Rede'
      WHEN dpce.product_origin = 'AGENT_PWA'
      THEN 'Agent'
      -- WHEN dpce.booking_creator = 'Agent' THEN 'Agent'
      -- WHEN bm.is_1p_demand = TRUE THEN 'Agent'
      -- WHEN bm.is_3p_demand = TRUE THEN 'Rede'
      ELSE dpce.booking_creator
    END AS operation_channel,
    CASE
      WHEN (dpce.product_origin = 'AGENT_PWA'
          AND dpce.id_agent = sef.id_agent
          AND (bcr.buyer_company_relation_type IS NULL OR bcr.buyer_company_relation_type != '3P'))
        OR dpce.utm_medium = 'TQC 1P'
      THEN
        CASE
          WHEN LOWER(dpce.business_context) = 'rent' THEN 'TQA 1P'
          ELSE 'TQC 1P'
        END
      WHEN dpce.utm_medium = 'TQC 3P'
        OR (dpce.product_origin = 'AGENT_PWA'
          AND bm.is_3p_demand = TRUE)
      THEN
        CASE
          WHEN LOWER(dpce.business_context) = 'rent' THEN 'TQA 3P'
          ELSE 'TQC 3P'
        END
      WHEN dpce.product_origin = 'AGENT_PWA'
        OR dpce.booking_creator = 'Agent'
      THEN 'Agent'
      ELSE 'NA'
    END AS referral_type,
    CASE
      WHEN dpce.product_origin IS NULL THEN 'Lost Tracking'
      ELSE dpce.product_origin
    END AS origin,
    CASE
      WHEN dpce.app_type IS NULL THEN "Lost Tracking"
      WHEN LOWER(dpce.app_type) LIKE '%android%' THEN 'App Android'
      WHEN LOWER(dpce.app_type) LIKE '%ios%' THEN 'App iOS'
      WHEN LOWER(dpce.app_type) LIKE '%web_desktop%' THEN 'Web Desktop'
      WHEN LOWER(dpce.app_type) LIKE '%web_mobile%' THEN 'Web Mobile'
      ELSE "Other"
    END AS platform,
    CASE
      WHEN dpce.entrance_uri LIKE '%/guias/%'
      THEN "guias"
    END AS content_page,
    dpce.ts_event,
    dpce.year,
    dpce.month,
    dpce.day
  FROM
    datalake_demand_flows.demand_prospect_conversion_events AS dpce
  LEFT JOIN
    company_relation AS bcr
    ON bcr.sk_user = dpce.id_prospect
    AND DATE(dpce.ts_event) BETWEEN DATE(bcr.ts_start) AND DATE(bcr.ts_end)
  LEFT JOIN
    datalake_tqc_referral.sale_events_flow AS sef
      ON dpce.visit_code = sef.visit_code
  LEFT JOIN
    business_model AS bm
      ON dpce.visit_code = bm.visit_code
  WHERE
    DATE(dpce.ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),

media_setup_ids AS (
  SELECT
    dpce.id_demand_prospect_conversion_event,
    dpce.id_prospect,
    dpce.business_context,
    dpce.sale_type,
    dpce.id_event_type,
    dpce.event_name,
    dpce.utm_adhoc_rule AS media_setup_from_adhoc,
    concat_ws('.', slice(split(dpce.utm_campaign, '[.]'), 2, 7)) AS media_setup_from_naming_convention,
    concat_ws('.', slice(split(ef.correct_utm_campaign, '[.]'), 2, 7)) AS media_setup_from_exception_flow,
    dict.naming_convention_sufix AS media_setup_from_dictionary,
    dpce.id_rent_flow,
    dpce.id_sale_flow,
    dpce.id_booking,
    dpce.id_visit,
    dpce.id_offer,
    dpce.id_talk_to_agent,
    dpce.id_house,
    dpce.id_region,
    dpce.id_owner,
    dpce.id_agent,
    dpce.utm_adhoc_rule,
    dpce.utm_campaign,
    dpce.utm_medium,
    dpce.utm_source,
    dpce.utm_term,
    dpce.utm_content,
    dpce.entrance_uri,
    dpce.app_type,
    dpce.booking_creator,
    dpce.product_origin,
    COALESCE(dpce.is_3p_demand, FALSE) AS is_3p_demand,
    COALESCE(dpce.is_1p_demand, FALSE) AS is_1p_demand,
    COALESCE(dpce.is_cqa_demand, FALSE) AS is_cqa_demand,
    dpce.operation_channel,
    dpce.referral_type,
    dpce.origin,
    dpce.platform,
    dpce.content_page,
    dpce.ts_event,
    dpce.year,
    dpce.month,
    dpce.day
  FROM
    adhoc_rules AS dpce
  LEFT JOIN
    datalake_growth_taxonomy.unified_taxonomy_dictionary AS dict
      ON COALESCE(SF_NORMALIZE_STRING(dpce.utm_campaign),0) = COALESCE(LOWER(dict.utm_campaign),0)
      AND COALESCE(SF_NORMALIZE_STRING(dpce.utm_source),0) = COALESCE(LOWER(dict.utm_source),0)
      AND COALESCE(SF_NORMALIZE_STRING(dpce.utm_medium),0) = COALESCE(LOWER(dict.utm_medium),0)
  LEFT JOIN
    datalake_gsheets_clean.taxonomy_demand_exception_flow AS ef
      ON COALESCE(LOWER(dpce.utm_campaign), 0) = COALESCE(LOWER(ef.utm_campaign), 0)
      AND COALESCE(LOWER(dpce.utm_source), 0) = COALESCE(LOWER(ef.utm_source), 0)
      AND COALESCE(LOWER(dpce.utm_medium), 0) = COALESCE(LOWER(ef.utm_medium), 0)
)

SELECT
  id_demand_prospect_conversion_event,
  id_prospect,
  business_context,
  sale_type,
  id_event_type,
  event_name,
  media_setup_from_adhoc,
  media_setup_from_dictionary,
  media_setup_from_exception_flow,
  media_setup_from_naming_convention,
  CASE
    WHEN media_setup_from_adhoc IS NOT NULL THEN media_setup_from_adhoc
    WHEN media_setup_from_exception_flow IS NOT NULL AND media_setup_from_exception_flow <> '' THEN media_setup_from_exception_flow
    WHEN media_setup_from_dictionary IS NOT NULL THEN media_setup_from_dictionary
    WHEN media_setup_from_naming_convention IS NOT NULL THEN media_setup_from_naming_convention
  END AS naming_convention_sufix,
  CASE
    WHEN media_setup_from_adhoc IS NOT NULL THEN "adhoc rule"
    WHEN media_setup_from_exception_flow IS NOT NULL AND media_setup_from_exception_flow <> '' THEN "exception flow"
    WHEN media_setup_from_dictionary IS NOT NULL THEN "dictionary"
    WHEN media_setup_from_naming_convention IS NOT NULL THEN "naming convention"
  END AS naming_convention_sufix_origin,
  id_rent_flow,
  id_sale_flow,
  id_booking,
  id_visit,
  id_offer,
  id_talk_to_agent,
  id_house,
  id_region,
  id_owner,
  id_agent,
  utm_adhoc_rule,
  utm_campaign,
  utm_medium,
  utm_source,
  utm_term,
  utm_content,
  entrance_uri,
  app_type,
  booking_creator,
  product_origin,
  is_3p_demand,
  is_1p_demand,
  is_cqa_demand,
  operation_channel,
  referral_type,
  origin,
  platform,
  content_page,
  ts_event,
  year,
  month,
  day
FROM
  media_setup_ids
