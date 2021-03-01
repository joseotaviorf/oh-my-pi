SELECT
    CAST(id AS INTEGER) AS id,
    app_type,
    utm_source,
    utm_medium,
    branded,
    category,
    flow,
    completion,
    origin,
    channel,
    medium,
    source,
    platform,
    CAST(flg_via_reschedule AS INTEGER) AS flg_via_reschedule,
    first_update_source
FROM
    datalake_gsheets_raw.taxonomy_demand