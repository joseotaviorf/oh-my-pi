SELECT
    NULLIF(utm_campaign,'') AS utm_campaign,
    NULLIF(utm_source, '') AS utm_source,
    NULLIF(utm_medium, '') AS utm_medium,
    NULLIF(correct_utm_camapign,'') AS correct_utm_campaign,
    NULLIF(responsible_team, '') AS responsible_team,
    NULLIF(author,'') AS author,
    NULLIF(TO_DATE(dt_created, 'yyyy-MM-dd'),'') AS dt_created
FROM
    datalake_gsheets_raw.taxonomy_demand_exception_flow
