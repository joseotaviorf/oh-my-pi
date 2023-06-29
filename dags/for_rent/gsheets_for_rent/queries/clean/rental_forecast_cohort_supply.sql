SELECT
    city_group,
    lead,
    mkt_channel,
    CAST(fl AS DECIMAL(12,4)) AS fl,
    CAST(op2q AS DECIMAL(12,4)) AS op2q,
    CAST(opp2fl AS DECIMAL(12,4)) AS opp2fl,
    CAST(q2opp AS DECIMAL(12,4)) AS q2opp,
    week_origin,
    TO_DATE(week_start, 'M/d/yyyy') AS dt_week_start
FROM
    datalake_gsheets_raw.forecast_cohort_supply