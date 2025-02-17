WITH pro_owner_history as (
  SELECT DISTINCT
    poh.id_owner,
    poh.is_pro_owner,
    poh.ts_pro_owner_started,
    poh.ts_pro_owner_ended
  FROM
    datalake_pro_owners.pro_owner_history AS poh
),
pp_multi_cluster AS (
  SELECT
    id_owner,
    cluster,
    ts_load
  FROM
    datalake_gsheets_clean.pp_multi_cluster
  QUALIFY
      ROW_NUMBER() OVER (PARTITION BY id_owner ORDER BY ts_load DESC) = 1
),
owner_house_category AS(
  SELECT
    ohqh.id_owner,
    ohqh.country_code,
    ohqh.ongoing_houses >= 5 AS has_5_or_more_ongoing_houses,
    CASE 
      WHEN poh.is_pro_owner THEN TRUE
      WHEN (poh.id_owner IS NULL 
        OR poh.is_pro_owner) THEN FALSE
      ELSE FALSE
    END AS is_pp_multi,
    CASE
      WHEN ohqh.id_owner = pmc.id_owner THEN pmc.cluster
      WHEN ohqh.ongoing_houses > 15 THEN 'Investors (15+)'
      WHEN ohqh.ongoing_houses >= 10 THEN 'Investors (10-15)'
      WHEN ohqh.ongoing_houses >= 5 THEN 'Long-tail (5-10)'
      ELSE 'Amateur'
    END AS cluster_pp_multi,
    ohqh.dt_houses_owned,
    ohqh.year,
    ohqh.month,
    ohqh.day
  FROM
    datalake_pro_owners.daily_owner_houses_quantity_history AS ohqh
  LEFT JOIN
    pro_owner_history AS poh
      ON ohqh.id_owner = poh.id_owner
      AND MAKE_DATE(ohqh.year, ohqh.month, ohqh.day) >= DATE(poh.ts_pro_owner_started)
      AND MAKE_DATE(ohqh.year, ohqh.month, ohqh.day) < COALESCE(DATE(poh.ts_pro_owner_ended), CURRENT_DATE())
  LEFT JOIN
    pp_multi_cluster AS pmc
      ON ohqh.id_owner = pmc.id_owner
  WHERE
    ohqh.year = {year}
    AND ohqh.month = {month}
    AND ohqh.day = {day}
),
owner_house_category_changes AS (
  SELECT
    id_owner,
    has_5_or_more_ongoing_houses,
    LAG(has_5_or_more_ongoing_houses) OVER (PARTITION BY id_owner ORDER BY year, month, day) AS previous_has_5_or_more_ongoing_houses,
    is_pp_multi,
    LAG(is_pp_multi) OVER (PARTITION BY id_owner ORDER BY year, month, day) AS previous_is_pp_multi,
    dt_houses_owned,
    year,
    month,
    day
  FROM
    owner_house_category
),
owner_category AS (
  SELECT
    id_owner,
    ROW_NUMBER() OVER (PARTITION BY id_owner ORDER BY year, month, day) AS owner_category,
    has_5_or_more_ongoing_houses,
    is_pp_multi,
    MAKE_DATE(year, month, day) AS dt_owner_category_started,
    LEAD(dt_houses_owned) OVER (PARTITION BY id_owner ORDER BY year, month, day) AS dt_owner_category_ended
  FROM
    owner_house_category_changes
  WHERE
    has_5_or_more_ongoing_houses <> previous_has_5_or_more_ongoing_houses
    OR is_pp_multi <> previous_is_pp_multi
),
current_category AS (
  SELECT
    id_owner,
    MAX(owner_category) AS last_category
  FROM
    owner_category
  GROUP BY 1
)
SELECT
  ohc.id_owner || 0 || COALESCE(oc.owner_category, 0) AS id_owner_category,
  ohc.id_owner,
  ohc.country_code,
  COALESCE(oc.owner_category, 0) AS owner_category,
  ohc.has_5_or_more_ongoing_houses,
  ohc.is_pp_multi,
  ohc.cluster_pp_multi,
  COALESCE(oc.owner_category, 0) = COALESCE(cc.last_category, 0) AS is_current_category,
  ohc.dt_houses_owned AS dt_owner_category,
  {year} AS year,
  {month} AS month,
  {day} AS day
FROM
  owner_house_category AS ohc
LEFT JOIN
  owner_category AS oc
    ON ohc.id_owner = oc.id_owner
    AND MAKE_DATE(ohc.year, ohc.month, ohc.day) >= oc.dt_owner_category_started
    AND MAKE_DATE(ohc.year, ohc.month, ohc.day) < COALESCE(oc.dt_owner_category_ended, CURRENT_DATE())
LEFT JOIN
  current_category AS cc
    ON ohc.id_owner = cc.id_owner