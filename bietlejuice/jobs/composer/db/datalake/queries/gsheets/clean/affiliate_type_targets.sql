SELECT
    active_users,
    city_group,
    cost,
    new_users,
    prospects,
    qualifieds,
    supply_origin,
    supply_type_of_user,
    tier,
    total_users,
    halfyear,
    quarter,
    week_start,
    month AS target_month,
    date AS target_date
FROM
    datalake_gsheets_raw.affiliate_type_targets
