WITH tof_events_merged AS (
  SELECT
    tof.ts_event,
    COALESCE(
        CAST(u.id_user AS VARCHAR(1000)),
        CAST(tof.id_user AS VARCHAR(1000)),
        CAST(tof.id_amplitude AS VARCHAR(1000))
    ) AS id_tof_user,
    tof_event_type,
    id_session,
    COALESCE(u.id_user,tof.id_user) AS id_user,
    tof.id_amplitude,
    id_device,
    utm_campaign,
    utm_medium,
    utm_source,
    LOWER(business_context) AS business_context,
    up_platform AS platform,
    COALESCE(CAST(ep_house_id AS STRING), top5_house_id[1]) AS id_house,
    ROW_NUMBER() OVER (
      PARTITION BY COALESCE(
        CAST(u.id_user AS VARCHAR(1000)),
        CAST(tof.id_user AS VARCHAR(1000)),
        CAST(tof.id_amplitude AS VARCHAR(1000))
        ) ORDER BY tof.ts_event) AS tof_event_order_at_all,
    ROW_NUMBER() OVER (
      PARTITION BY COALESCE(
        CAST(u.id_user AS VARCHAR(1000)),
        CAST(tof.id_user AS VARCHAR(1000)),
        CAST(tof.id_amplitude AS VARCHAR(1000))
        ), LOWER(business_context) ORDER BY tof.ts_event) AS tof_event_order_per_business_context,
    tof.year,
    tof.month,
    tof.day
  FROM
    datalake_amplitude_page_viewed_events.schedule_search_listing_events AS tof
  LEFT JOIN
    original_user_merge AS u
      ON u.id_amplitude_all = tof.id_amplitude
  WHERE
    tof.YEAR >= YEAR(CURRENT_DATE) - 1
),
filtered_taxonomy_dict AS (
  SELECT
    naming_convention_sufix,
    utm_campaign,
    utm_source,
    utm_medium
  FROM
    datalake_growth_taxonomy.unified_taxonomy_dictionary
  WHERE
    (
      utm_campaign IS NOT NULL
      OR utm_source IS NOT NULL
      OR utm_medium IS NOT NULL
    )
),
-- include marketing campaigns naming convention for event attribution
tof_users_merged_with_naming_convention AS (
  SELECT
    tof.ts_event,
    tof.id_tof_user,
    tof.id_session,
    tof.id_user,
    tof.id_amplitude,
    tof.id_device,
    tof.business_context,
    tof.tof_event_type,
    CASE
      WHEN (tof.utm_campaign IS NULL AND tof.utm_source IS NULL AND tof.utm_medium IS NULL AND tof.platform IS NULL) THEN "ZEBRA.lost.los.lostra.lostra.l.losttracking.losttracking"
      WHEN (tof.utm_campaign IS NULL AND tof.utm_source IS NULL AND tof.utm_medium IS NULL AND tof.platform IS NOT NULL) THEN "ZEBRA.na.acq.org.na.d.direct.na"
      ELSE COALESCE(ef.correct_utm_campaign, CONCAT('ZEBRA.', dict.naming_convention_sufix), CONCAT('ZEBRA.', tof.utm_campaign), 'Not Mapped')
    END AS naming_convention_sufix,
    tof.utm_campaign,
    tof.utm_medium,
    tof.utm_source,
    tof.id_house,
    tof.platform,
    tof.tof_event_order_at_all,
    tof.tof_event_order_per_business_context,
    tof.year,
    tof.month,
    tof.day
  FROM
    tof_events_merged AS tof
  LEFT JOIN
    datalake_gsheets_clean.taxonomy_demand_exception_flow AS ef
      ON COALESCE(SF_NORMALIZE_STRING(tof.utm_campaign),0) = COALESCE(SF_NORMALIZE_STRING(ef.utm_campaign),0)
      AND COALESCE(SF_NORMALIZE_STRING(tof.utm_source),0) = COALESCE(SF_NORMALIZE_STRING(ef.utm_source),0)
      AND COALESCE(SF_NORMALIZE_STRING(tof.utm_medium),0) = COALESCE(SF_NORMALIZE_STRING(ef.utm_medium),0)
  LEFT JOIN
    filtered_taxonomy_dict AS dict
      ON COALESCE(SF_NORMALIZE_STRING(tof.utm_campaign),0) = COALESCE(SF_NORMALIZE_STRING(dict.utm_campaign),0)
      AND COALESCE(SF_NORMALIZE_STRING(tof.utm_source),0) = COALESCE(SF_NORMALIZE_STRING(dict.utm_source),0)
      AND COALESCE(SF_NORMALIZE_STRING(tof.utm_medium),0) = COALESCE(SF_NORMALIZE_STRING(dict.utm_medium),0)
),
dim_media_setup_dedup AS (
  SELECT
    ms.naming_convention_sufix,
    ms.campaign_business_context,
    ms.funnel_side,
    ms.campaign_strategy_intent,
    ms.behavior_type,
    ms.medium,
    ms.source,
    ms.ts_load
FROM
  datalake_growth_taxonomy.media_setup AS ms
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY ms.naming_convention_sufix ORDER BY ms.ts_load DESC) = 1
)
-- include taxonomy data
SELECT
  tof.id_tof_user,
  tof.id_session,
  tof.id_user,
  tof.id_amplitude,
  tof.id_device,
  tof.id_house,
  tof.business_context,
  tof.tof_event_type,
  'SelfService' AS operation_channel,
  tof.platform,
  dms.funnel_side,
  dms.campaign_business_context,
  dms.campaign_strategy_intent,
  dms.behavior_type,
  dms.medium,
  dms.source,
  COALESCE(dtma.taxonomy_aggregation_level_1, 'Other') AS taxonomy_aggregation_level_1,
  COALESCE(dtma.taxonomy_aggregation_level_2, 'Other') AS taxonomy_aggregation_level_2,
  tof.tof_event_order_at_all,
  tof.tof_event_order_per_business_context,
  tof.ts_event,
  tof.year,
  tof.month,
  tof.day
FROM
  tof_users_merged_with_naming_convention AS tof
LEFT JOIN
  dim_media_setup_dedup AS dms
    ON CONCAT_WS('.', SLICE(SPLIT(tof.naming_convention_sufix, '[.]'), 2, 7)) = dms.naming_convention_sufix
LEFT JOIN
  datalake_gsheets_clean.taxonomy_management_aggregation AS dtma
    ON dms.funnel_side = dtma.funnel_side
    AND dms.campaign_business_context = dtma.campaign_business_context
    AND dms.campaign_strategy_intent = dtma.campaign_strategy_intent
    AND dms.behavior_type = dtma.behavior_type
    AND dms.medium = dtma.medium
