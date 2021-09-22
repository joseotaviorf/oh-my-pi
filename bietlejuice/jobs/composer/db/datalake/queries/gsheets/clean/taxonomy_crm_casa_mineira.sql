SELECT
    CAST(id AS INTEGER) AS id,
    origin_contact_name,
    media_contact_name,
    mkt_origin,
    mkt_channel,
    mkt_medium,
    mkt_source
FROM
    datalake_gsheets_raw.taxonomy_crm_casa_mineira