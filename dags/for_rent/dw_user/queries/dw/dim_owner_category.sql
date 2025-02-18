SELECT
  id_owner_category AS sk_owner_category,
  id_owner AS sk_owner,
  country_code,
  has_5_or_more_ongoing_houses,
  is_pp_multi,
  is_current_category,
  dt_owner_category_started,
  dt_owner_category_ended,
  NOW() AS ts_load
FROM
  datalake_pro_owners.owner_category
