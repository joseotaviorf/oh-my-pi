SELECT
    city_group,
    tier,
    business,
    supply_origin,
    supply_type_of_user,
    new_users,
    active_users,
    total_users,
    prospects,
    qualifieds,
    cost,
    CAST(target_month AS INTEGER) AS target_month,
    CAST(quarter AS INTEGER) AS quarter,
    CAST(half_year AS INTEGER) AS half_year,
    DATE(target_date) AS dt_target,
    DATE(week_start) AS dt_week_started
FROM
    datalake_gsheets_raw.affiliate_type_targets
