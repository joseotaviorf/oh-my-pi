SELECT
    CAST(id AS INTEGER) AS id,
    app_type,
    utm_source,
    utm_medium,
    branded,
    mkt_category,
    mkt_flow,
    mkt_completion,
    mkt_origin,
    mkt_channel,
    mkt_medium,
    mkt_source,
    mkt_platform
FROM
    datalake_gsheets_raw.taxonomy_portal_casa_mineira