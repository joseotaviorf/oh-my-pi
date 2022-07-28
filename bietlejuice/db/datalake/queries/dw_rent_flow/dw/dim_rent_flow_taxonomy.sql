SELECT
    CAST(id AS BIGINT) AS sk_rent_flow_taxonomy,
    CAST(id AS BIGINT) AS id_rent_flow_taxonomy,
    category AS mkt_category,
    flow AS mkt_flow,
    completion AS mkt_completion,
    origin AS mkt_origin,
    channel AS mkt_channel,
    medium AS mkt_medium,
    source AS mkt_source,
    platform AS mkt_platform,
    NOW() AS ts_load
FROM datalake_gsheets_clean.taxonomy_demand