WITH all_metrics AS (
  /*  Facebook Metrics */
  SELECT
    *
  FROM datalake_growth_media_platform.facebook_metrics
  WHERE
    CAST(dt_cost AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
  UNION ALL
  /* Criteo Metrics */
  SELECT
    *
  FROM datalake_growth_media_platform.criteo_metrics
  WHERE
    CAST(dt_cost AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
    AND state <> 'Unknown'
  /* Google Ads Metrics */
  UNION ALL
  SELECT
    *
  FROM datalake_growth_media_platform.google_metrics
  WHERE
    CAST(dt_cost AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
  /* Trovit Metrics */
  UNION ALL
  SELECT
    *
  FROM datalake_growth_media_platform.trovit_metrics
  WHERE
    CAST(dt_cost AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
    AND SPLIT(utm_campaign, '[.]')[0] <> 'ZEBRA'
    AND year >= 2023
), translation_dictionary AS (
  SELECT
    account_name,
    utm_campaign,
    origin,
    campaign_name_convention
  FROM (
    SELECT
      account_name,
      campaign_name AS utm_campaign,
      origin,
      campaign_name_convention,
      ROW_NUMBER() OVER (PARTITION BY account_name, campaign_name, origin ORDER BY campaign_name_convention) AS _w,
      campaign_name
    FROM datalake_gsheets_clean.cost_taxonomy_translation_dictionary
    GROUP BY ALL
  ) AS _t
  WHERE
    _w = 1
), scd AS (
  SELECT
    id_campaign,
    origin,
    current_campaign_name,
    last_campaign_name,
    dt_campaign_name_last_change
  FROM (
    SELECT
      id_campaign,
      origin,
      IF(is_current = TRUE, campaign_name, NULL) AS current_campaign_name,
      LAG(campaign_name) OVER (PARTITION BY id_campaign, origin ORDER BY dt_start ASC) AS last_campaign_name,
      LAG(dt_end) OVER (PARTITION BY id_campaign, origin ORDER BY dt_start ASC) AS dt_campaign_name_last_change
    FROM datalake_growth_media_platform.campaign_name_history
  ) AS _t
  WHERE
    NOT current_campaign_name IS NULL
), criteo_unknown_costs AS (
  SELECT
    dt_cost,
    id_campaign,
    id_adset,
    SUM(CASE WHEN state = 'Unknown' THEN total_cost END) AS unknown_costs,
    SUM(CASE WHEN state = 'Unknown' THEN impressions END) AS unknown_impressions,
    SUM(CASE WHEN state = 'Unknown' THEN clicks END) AS unknown_clicks,
    SUM(CASE WHEN state <> 'Unknown' THEN total_cost END) AS total_costs_without_unknown_costs,
    SUM(CASE WHEN state <> 'Unknown' THEN impressions END) AS impressions_without_unknown_costs,
    SUM(CASE WHEN state <> 'Unknown' THEN clicks END) AS clicks_without_unknown_costs
  FROM datalake_growth_media_platform.criteo_metrics
  WHERE
    CAST(dt_cost AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
  GROUP BY ALL
), region AS (
  SELECT
    id_region,
    city_name_sanitized,
    city_group
  FROM (
    SELECT
      id AS id_region,
      SF_NORMALIZE_STRING(city_name) AS city_name_sanitized,
      city_group,
      ROW_NUMBER() OVER (PARTITION BY SF_NORMALIZE_STRING(city_name) ORDER BY id) AS _w,
      id
    FROM datalake_region.region
  ) AS _t
  WHERE
    _w = 1
), base_costs AS (
  SELECT
    am.id_account,
    am.id_campaign,
    am.id_adset,
    am.id_ad,
    CASE
      WHEN am.origin = 'trovit'
      THEN TRY_CAST(REGEXP_EXTRACT(am.utm_campaign, '^(\\d+)[.]') AS INT)
      WHEN city_group IS NULL AND state = 'Bahia'
      THEN 2922
      WHEN city_group IS NULL AND state = 'Santa Catarina'
      THEN 2039
      WHEN city_group IS NULL AND state IN ('Distrito Federal', 'Federal District')
      THEN 1514
      WHEN city_group IS NULL AND state IN ('Goiás', 'Goias', 'GoiÃ¡s')
      THEN 1522
      WHEN city_group IS NULL AND state IN ('Paraná', 'Parana', 'ParanÃ¡')
      THEN 1918
      WHEN city_group IS NULL AND state = 'Minas Gerais'
      THEN 1535
      WHEN city_group IS NULL AND state = 'Rio de Janeiro'
      THEN 1494
      WHEN city_group IS NULL AND state = 'Rio Grande do Sul'
      THEN 1842
      WHEN city_group IS NULL AND state IN ('Sao Paulo', 'São Paulo', 'SÃ£o Paulo')
      THEN 39
      ELSE COALESCE(region.id_region, -1)
    END AS id_region,
    am.account_name,
    am.origin,
    am.report_type,
    am.utm_campaign,
    am.utm_term,
    am.utm_content,
    am.country_code,
    CASE
      WHEN NOT td.campaign_name_convention IS NULL
      THEN 'sufix_from_dictionary'
      WHEN NOT NULLIF(CONCAT_WS('.', SLICE(SPLIT(am.utm_campaign, '[.]'), 2, 7)), '') IS NULL
      THEN 'sufix_from_campaign'
      ELSE 'not_mapped'
    END AS type_flow_media_setup,
    COALESCE(
      td.campaign_name_convention /* sufix_from_dictionary, */,
      NULLIF(CONCAT_WS('.', SLICE(SPLIT(am.utm_campaign, '[.]'), 2, 7)), '') /* sufix_from_campaign */
    ) AS naming_convention_sufix,
    scd.current_campaign_name,
    scd.last_campaign_name,
    scd.dt_campaign_name_last_change,
    am.dt_cost,
    am.year,
    am.month,
    am.day,
    SUM(am.clicks) AS clicks,
    SUM(am.conversions) AS conversions,
    SUM(am.impressions) AS impressions,
    SUM(am.total_cost) AS total_cost
  FROM all_metrics AS am
  LEFT JOIN translation_dictionary AS td
    ON (
      am.origin = td.origin
    )
    AND (
      am.account_name = td.account_name
    )
    AND (
      am.utm_campaign = td.utm_campaign
    )
  LEFT JOIN scd
    ON scd.id_campaign = am.id_campaign AND scd.origin = am.origin
  LEFT JOIN region
    ON region.city_name_sanitized = SF_NORMALIZE_STRING(am.city)
  WHERE
    (
      clicks > 0 OR conversions > 0 OR impressions > 0 OR total_cost > 0
    )
  GROUP BY ALL
), rateio_unknown_costs AS (
  SELECT
    bcn.id_campaign,
    bcn.id_adset,
    bcn.dt_cost,
    bcn.id_region,
    unknown_costs,
    total_costs_without_unknown_costs,
    unknown_impressions,
    unknown_clicks,
    impressions_without_unknown_costs,
    clicks_without_unknown_costs,
    CASE
      WHEN COALESCE(total_costs_without_unknown_costs, 0.0) = 0
      OR COALESCE(unknown_costs, 0.0) = 0
      THEN 0
      ELSE (
        SUM(total_cost) / total_costs_without_unknown_costs
      ) * unknown_costs
    END AS unknown_costs_city_group,
    CASE
      WHEN COALESCE(impressions_without_unknown_costs, 0.0) = 0
      OR COALESCE(unknown_impressions, 0.0) = 0
      THEN 0
      ELSE (
        SUM(impressions) / impressions_without_unknown_costs
      ) * unknown_impressions
    END AS unknown_impressions_city_group,
    CASE
      WHEN COALESCE(clicks_without_unknown_costs, 0.0) = 0
      OR COALESCE(unknown_clicks, 0.0) = 0
      THEN 0
      ELSE (
        SUM(clicks) / clicks_without_unknown_costs
      ) * unknown_clicks
    END AS unknown_clicks_city_group
  FROM base_costs AS bcn
  LEFT JOIN criteo_unknown_costs AS uc
    ON bcn.id_campaign = uc.id_campaign
    AND bcn.id_adset = uc.id_adset
    AND bcn.dt_cost = uc.dt_cost
  WHERE
    origin = 'criteo'
  GROUP BY ALL
)
SELECT
  bc.id_account,
  bc.id_campaign,
  bc.id_adset,
  bc.id_ad,
  bc.id_region,
  bc.account_name,
  bc.origin,
  bc.report_type,
  bc.utm_campaign,
  bc.utm_term,
  bc.utm_content,
  bc.country_code,
  bc.total_cost + COALESCE(unknown_costs_city_group, 0) AS total_cost,
  bc.impressions + COALESCE(unknown_impressions_city_group, 0) AS impressions,
  bc.clicks + COALESCE(unknown_clicks_city_group, 0) AS clicks,
  bc.conversions,
  bc.naming_convention_sufix,
  bc.current_campaign_name,
  bc.last_campaign_name,
  bc.dt_campaign_name_last_change,
  bc.dt_cost,
  bc.year,
  bc.month,
  bc.day
FROM base_costs AS bc
LEFT JOIN rateio_unknown_costs AS ruc
  ON bc.id_campaign = ruc.id_campaign
  AND bc.id_adset = ruc.id_adset
  AND bc.dt_cost = ruc.dt_cost
  AND bc.id_region = ruc.id_region
  AND bc.origin = 'criteo'