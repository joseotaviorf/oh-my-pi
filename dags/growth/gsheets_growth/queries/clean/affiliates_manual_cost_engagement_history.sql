SELECT
    city_group,
    mkt_origin,
    FLOAT(commission_listing) AS commission_listing_cost,
    FLOAT(commission_rent) AS commission_rent_cost,
    FLOAT(commission_mgm) AS commission_mgm_cost,
    FLOAT(promotional_bonus) AS promotional_bonus_cost,
    FLOAT(notification) AS notification_cost,
    FLOAT(other) AS other_cost,
    DATE(date) AS dt_cost
FROM
    datalake_gsheets_raw.manual_cost_engagement_history
