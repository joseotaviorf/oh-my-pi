WITH pro_owner_history as (
  SELECT DISTINCT
    poh.id_owner,
    poh.is_pro_owner,
    poh.ts_pro_owner_started,
    poh.ts_pro_owner_ended
  FROM
    datalake_pro_owners.pro_owner_history AS poh
),
owner_house_category AS(
  SELECT
    ohqh.id_owner,
    ohqh.country_code,
    IF(ohqh.ongoing_houses < 5, '<5', '>=5') AS category,
    poh.id_owner IS NULL
      OR poh.is_pro_owner = FALSE AS is_amateur,
    COALESCE(poh.is_pro_owner, FALSE) AS is_pp_multi_active,
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
),
owner_house_category_changes AS (
  SELECT
    id_owner,
    category,
    LAG(category) OVER (PARTITION BY id_owner ORDER BY year, month, day) AS previous_category,
    is_amateur,
    LAG(is_amateur) OVER (PARTITION BY id_owner ORDER BY year, month, day) AS previous_is_amateur,
    is_pp_multi_active,
    LAG(is_pp_multi_active) OVER (PARTITION BY id_owner ORDER BY year, month, day) AS previous_is_pp_multi_active,
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
    category,
    is_amateur,
    is_pp_multi_active,
    year, 
    month, 
    day,
    LEAD(dt_houses_owned) OVER (PARTITION BY id_owner ORDER BY year, month, day) AS dt_owner_category_ended
  FROM
    owner_house_category_changes
  WHERE
    category <> previous_category
    OR is_amateur <> previous_is_amateur
    OR is_pp_multi_active <> previous_is_pp_multi_active
) 

SELECT
  ohc.id_owner || 0 || COALESCE(ov.owner_category, 0) AS id_owner_category,
  ohc.id_owner,
  ohc.category,
  ohc.country_code,
  COALESCE(ov.owner_category, 0) AS owner_category,
  ohc.is_amateur,
  ohc.is_pp_multi_active,
  ohc.dt_houses_owned AS dt_owner_category,
  ohc.year,
  ohc.month,
  ohc.day
FROM
  owner_house_category AS ohc
LEFT JOIN
  owner_category AS ov
    ON ohc.id_owner = ov.id_owner
    AND MAKE_DATE(ohc.year, ohc.month, ohc.day) >= MAKE_DATE(ov.year, ov.month, ov.day)
    AND MAKE_DATE(ohc.year, ohc.month, ohc.day) < COALESCE(dt_owner_category_ended, CURRENT_DATE())