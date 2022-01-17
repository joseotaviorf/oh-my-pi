SELECT
    NULLIF(Medium,'') AS mkt_medium,
    NULLIF(Source,'') AS mkt_source,
    CAST(REPLACE(Budget, ',', '') AS FLOAT) AS cost_target,
    CAST(REPLACE(CF, ',', '') AS FLOAT) AS contact_flow_target,
    CAST(NULLIF(REPLACE(TOF, ',', ''), '') AS FLOAT) AS top_of_funnel_target,
    CAST(NULLIF(Data,'') AS DATE) AS dt_target
FROM
    datalake_gsheets_raw.targets_portal_casa_mineira