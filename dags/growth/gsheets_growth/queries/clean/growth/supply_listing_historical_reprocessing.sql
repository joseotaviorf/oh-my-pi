SELECT
    CAST(NULLIF(base,'') AS STRING) AS base,
    CAST(NULLIF(id_house, '') AS BIGINT) AS id_house,
    CAST(NULLIF(telefone_principal, '') AS BIGINT) AS main_phone,
    CAST(NULLIF(sales_company,'') AS STRING) AS sales_company,
    CAST(NULLIF(sk_lead, '') AS BIGINT) AS sk_lead,
    CAST(NULLIF(data_mailing, '') AS DATE) AS dt_mailing
FROM
    datalake_gsheets_raw.supply_listing_historical_reprocessing
