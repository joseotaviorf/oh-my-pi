WITH taxonomy_combinations AS (
  SELECT
    NULL AS id_media_setup,
    fs.value AS funnel_side,
    ci.value AS campaign_strategy_intent,
    ct.value AS campaign_business_context,
    lp.value AS campaign_landing_page,
    bt.value AS behavior_type,
    m.value AS medium,
    src.value AS source
  FROM
    datalake_gsheets_clean.taxonomy_levels_values AS fs
  CROSS JOIN
    datalake_gsheets_clean.taxonomy_levels_values  AS ct
  CROSS JOIN
    datalake_gsheets_clean.taxonomy_levels_values  AS lp
  CROSS JOIN
    datalake_gsheets_clean.taxonomy_levels_values  AS ci
  CROSS JOIN
    datalake_gsheets_clean.taxonomy_levels_values  AS bt
  CROSS JOIN
    datalake_gsheets_clean.taxonomy_levels_values  AS m
  CROSS JOIN
    datalake_gsheets_clean.taxonomy_levels_values  AS src
  WHERE
    fs.taxonomy_level = 'funnel_side'
    AND ct.taxonomy_level = 'campaign_business_context'
    AND ci.taxonomy_level = 'campaign_strategy_intent'
    AND bt.taxonomy_level = 'behavior_type'
    AND m.taxonomy_level = 'medium'
    AND src.taxonomy_level = 'source'
    AND lp.taxonomy_level = 'landing_page'
),
naming_convention_prefixes AS (
  SELECT
    id_media_setup,
    LOWER(LEFT(campaign_strategy_intent,3)) AS prefix_campaign_strategy_intent,
    LOWER(COALESCE(LEFT(SPLIT(behavior_type, " ")[0],3) ||LEFT(SPLIT(behavior_type, " ")[1],3), LEFT(behavior_type, 3))) AS prefix_behavior_type,
    LOWER(COALESCE(LEFT(SPLIT(campaign_landing_page, " ")[0],3) ||LEFT(SPLIT(campaign_landing_page, " ")[1],3), LEFT(campaign_landing_page, 3))) AS prefix_campaign_landing_page,
    LOWER(LEFT(campaign_business_context,4)) AS prefix_campaign_business_context,
    LOWER(LEFT(REPLACE(medium, ' ', ''), 20)) AS prefix_medium,
    LOWER(LEFT(REPLACE(source, ' ', ''), 20)) AS prefix_source,
    LOWER(LEFT(funnel_side,1)) AS prefix_funnel_side,
    campaign_strategy_intent,
    behavior_type,
    campaign_business_context,
    campaign_landing_page,
    medium,
    source,
    funnel_side
  FROM
    taxonomy_combinations
),

last_id_values AS (
    SELECT
        COALESCE(MAX(id_media_setup), 0) AS max_id_media_setup
    FROM
        datalake_growth_taxonomy.media_setup
)

SELECT
  COALESCE(
      nc.id_media_setup,
      ms.id_media_setup,
      liv.max_id_media_setup + MONOTONICALLY_INCREASING_ID() + 1
  ) AS id_media_setup,
  CONCAT_WS(".",
      nc.prefix_campaign_business_context,
      nc.prefix_campaign_strategy_intent,
      nc.prefix_behavior_type,
      nc.prefix_campaign_landing_page,
      nc.prefix_funnel_side,
      nc.prefix_medium,
      nc.prefix_source
  ) AS naming_convention_sufix,
  nc.campaign_business_context,
  nc.campaign_strategy_intent,
  nc.behavior_type,
  nc.campaign_landing_page,
  nc.funnel_side,
  nc.medium,
  nc.source,
  nc.prefix_campaign_business_context,
  nc.prefix_campaign_strategy_intent,
  nc.prefix_behavior_type,
  nc.prefix_campaign_landing_page,
  nc.prefix_funnel_side,
  nc.prefix_medium,
  nc.prefix_source,
  COALESCE(ms.ts_combination_created, NOW()) AS ts_combination_created,
  NOW() AS ts_load
FROM
  naming_convention_prefixes AS nc
CROSS JOIN
  last_id_values AS liv
LEFT JOIN
  datalake_growth_taxonomy.media_setup AS ms
    ON nc.campaign_business_context = ms.campaign_business_context
      AND nc.campaign_strategy_intent = ms.campaign_strategy_intent
      AND nc.campaign_landing_page = ms.campaign_landing_page
      AND nc.behavior_type = ms.behavior_type
      AND nc.medium = ms.medium
      AND nc.source = ms.source
      AND nc.funnel_side = ms.funnel_side