SELECT
    city_group,
    rental_administrator,
    business_type,
    rent_flow_origin,
    weeks_conversion,
    vb2vc,
    vc2os,
    os2oa,
    oa2ca,
    ca2cs,
    cs,
    vb2os,
    TO_DATE(week_start) AS dt_week_started
FROM
    datalake_gsheets_raw.demand_targets_2024_cohort
