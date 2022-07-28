SELECT
    CAST(id_house AS BIGINT) AS id_house,
    plaquinha_type,
    installation_type,
    listing_type,
    DATE(date) AS dt_plaquinha
FROM
    datalake_gsheets_raw.branding_where_is_plaquinha