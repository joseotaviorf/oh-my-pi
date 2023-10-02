WITH previous_categories AS (
  SELECT
    id_owner_category,
    id_owner,
    has_5_or_more_ongoing_houses,
    LAG(has_5_or_more_ongoing_houses) OVER (PARTITION BY id_owner ORDER BY dt_owner_category) AS previous_has_5_or_more_ongoing_houses,
    is_pp_multi,
    LAG(is_pp_multi) OVER (PARTITION BY id_owner ORDER BY dt_owner_category) AS previous_is_pp_multi,
    is_current_category,
    dt_owner_category
  FROM
    datalake_pro_owners.daily_owner_category
)
SELECT
  pc.id_owner_category AS sk_owner_category,
  pc.id_owner AS sk_owner,
  COALESCE(u.country_code, 'Undefined') AS country_code,
  pc.has_5_or_more_ongoing_houses,
  pc.is_pp_multi,
  pc.is_current_category,
  pc.dt_owner_category AS dt_owner_category_started,
  LEAD(pc.dt_owner_category) OVER (PARTITION BY pc.id_owner ORDER BY pc.dt_owner_category) AS dt_owner_category_ended,
  NOW() AS ts_load
FROM
  previous_categories AS pc
LEFT JOIN
  datalake_ebdb_country.user AS u
    ON pc.id_owner = u.id_user
WHERE
  (has_5_or_more_ongoing_houses <> previous_has_5_or_more_ongoing_houses OR previous_has_5_or_more_ongoing_houses IS NULL)
  OR (is_pp_multi <> previous_is_pp_multi OR previous_is_pp_multi IS NULL)