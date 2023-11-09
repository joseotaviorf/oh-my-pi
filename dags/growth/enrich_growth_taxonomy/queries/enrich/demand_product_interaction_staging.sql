WITH content_page AS (
  SELECT
    value AS content_page
  FROM 
    datalake_gsheets_clean.taxonomy_levels_values
  WHERE 
    taxonomy_level = 'content_page'
),

demand_origins AS (
  SELECT DISTINCT
    name AS origin
  FROM
    datalake_ebdb_clean.visit_origin
),

mapped_app_types AS (
  SELECT DISTINCT 
    app_type
  FROM 
    datalake_amplitude_visit.amplitude_visit
),

business_rules AS (
  SELECT
    CONCAT_WS("#",
      COALESCE(LOWER(origin), 0),
      COALESCE(LOWER(app_type), 0),
      COALESCE(LOWER(content_page), 0)
    ) AS bk_product_interaction,
    origin,
    CASE
      WHEN app_type IS NULL THEN "Lost Tracking"
      WHEN LOWER(app_type) LIKE '%android%' THEN 'App Android'
      WHEN LOWER(app_type) LIKE '%ios%' THEN 'App iOS'
      WHEN LOWER(app_type) LIKE '%web_desktop%' THEN 'Web Desktop'
      WHEN LOWER(app_type) LIKE '%web_mobile%' THEN 'Web Mobile'
      ELSE "Other"
    END AS platform,
    content_page
  FROM
    mapped_app_types
  CROSS JOIN
    demand_origins
  CROSS JOIN
    content_page
),

last_id_values AS (
  SELECT
      COALESCE(MAX(id_demand_product_interaction), 0) AS max_id_demand_product_interaction
  FROM
    datalake_growth_taxonomy.demand_product_interaction 
)

SELECT
  COALESCE(
      dup.id_demand_product_interaction,
      liv.max_id_demand_product_interaction + MONOTONICALLY_INCREASING_ID() + 1
  ) AS id_demand_product_interaction,
  br.bk_product_interaction,
  br.origin,
  br.platform,
  br.content_page,
  COALESCE(dup.ts_combination_created, NOW()) AS ts_combination_created,
  NOW() AS ts_load
FROM
  business_rules AS br
CROSS JOIN
  last_id_values AS liv
LEFT JOIN
  datalake_growth_taxonomy.demand_product_interaction AS dup
    ON br.origin = dup.origin
    AND br.platform = dup.platform
    AND br.content_page = dup.content_page