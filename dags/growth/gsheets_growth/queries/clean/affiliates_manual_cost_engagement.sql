SELECT
    city_group,
    mkt_origin,
    FLOAT(promotional_bonus) AS promotional_bonus_cost,
    FLOAT(notification) AS notification_cost,
    FLOAT(other) AS other_cost,
    DATE(date) AS dt_cost
FROM
    datalake_gsheets_raw.manual_cost_engagement
