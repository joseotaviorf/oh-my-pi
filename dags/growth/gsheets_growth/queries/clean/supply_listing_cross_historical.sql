SELECT
    CAST(NULLIF(id_house, '') AS BIGINT) AS id_house,
    CAST(NULLIF(telefone_principal, '') AS BIGINT) AS main_phone,
    CAST(NULLIF(contexto_reprocessamento,'') AS STRING) AS reprocessing_context,
    CAST(NULLIF(sales_company,'') AS STRING) AS sales_company,
    CAST(NULLIF(data_mailing, '') AS DATE) AS dt_mailing
FROM
    datalake_gsheets_raw.supply_listing_cross_historical
