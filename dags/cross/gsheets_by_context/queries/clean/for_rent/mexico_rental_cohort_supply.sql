SELECT
    city_group,
    first_listing,
    mkt_channel,
    mkt_origin,
    operacao,
    rental_administrator,
    opportunities,
    prospect,
    qualified,
    available_qualifieds,
    CAST(year AS INTEGER) AS year,
    week_origin,
    TO_DATE(week, 'yyyy-MM-dd') AS dt_week_started
FROM
    datalake_gsheets_raw.mexico_rental_cohort_supply