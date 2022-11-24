SELECT
  city_group,
  tier,
  supply_origin,
  type_of_user,
  supply_channel,
  supply_medium,
  supply_source,
  new_active_users,
  cost_per_source,
  CAST(target_month AS INTEGER) AS target_month,
  CAST(quarter AS INTEGER) AS quarter,
  CAST(half_year AS INTEGER) AS half_year,
  DATE(target_date) AS dt_target,
  DATE(week_start) AS dt_week_started
FROM
  datalake_gsheets_raw.acquisition_target_per_source
