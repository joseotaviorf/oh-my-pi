WITH previous_categories AS (
  SELECT
    id_owner,
    country_code,
    has_5_or_more_ongoing_houses,
    LAG(has_5_or_more_ongoing_houses) OVER (PARTITION BY id_owner ORDER BY dt_owner_category) AS previous_has_5_or_more_ongoing_houses,
    is_pp_multi,
    LAG(is_pp_multi) OVER (PARTITION BY id_owner ORDER BY dt_owner_category) AS previous_is_pp_multi,
    dt_owner_category
  FROM
    datalake_pro_owners.daily_owner_category
),
owner_category AS (
  SELECT
    id_owner,
    ROW_NUMBER() OVER (PARTITION BY id_owner ORDER BY dt_owner_category) AS owner_category,
    country_code,
    has_5_or_more_ongoing_houses,
    is_pp_multi,
    dt_owner_category AS dt_owner_category_started,
    LEAD(dt_owner_category) OVER (PARTITION BY id_owner ORDER BY dt_owner_category) AS dt_owner_category_ended
  FROM
    previous_categories
  WHERE
    ((has_5_or_more_ongoing_houses <> previous_has_5_or_more_ongoing_houses OR previous_has_5_or_more_ongoing_houses IS NULL)
    OR (is_pp_multi <> previous_is_pp_multi OR previous_is_pp_multi IS NULL))
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
  oc.id_owner || 0 || COALESCE(oc.owner_category, 0) AS id_owner_category,
  oc.id_owner,
  oc.country_code,
  oc.owner_category,
  oc.has_5_or_more_ongoing_houses,
  oc.is_pp_multi,
  COALESCE(oc.owner_category, 0) = COALESCE(cc.last_category, 0) AS is_current_category,
  oc.dt_owner_category_started,
  oc.dt_owner_category_ended
FROM
  owner_category AS oc
LEFT JOIN
  current_category AS cc
    ON oc.id_owner = cc.id_owner
