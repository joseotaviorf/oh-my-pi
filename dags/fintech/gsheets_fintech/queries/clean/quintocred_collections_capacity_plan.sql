SELECT
    NULLIF(internal_team, '') AS internal_team,
    NULLIF(outsourcing, '') AS outsourcing,
    NULLIF(iaf_subscriptions, '') AS iaf_subscriptions,
    NULLIF(iaf_active, '') AS iaf_active,
    NULLIF(iaf_termination, '') AS iaf_termination,
    NULLIF(iaf_evictions, '') AS iaf_evictions,
    NULLIF(seman, '') AS week,
    NULLIF(mes, '') AS month,
    NULLIF(dia_util, '') AS business_day,
    TO_DATE(data, 'dd-MM-yyyy') AS dt_reference
FROM
    datalake_gsheets_raw.quintocred_collections_capacity_plan
