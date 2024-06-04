SELECT
    CAST(NULLIF(sk_lead, '') AS BIGINT) AS id_lead,
    CAST(NULLIF(id_house, '') AS BIGINT) AS id_house,
    CAST(NULLIF(base,'') AS STRING) AS base,
    CAST(NULLIF(tipo_de_base, '') AS STRING) AS base_type,
    CAST(NULLIF(telefone_principal, '') AS BIGINT) AS main_phone,
    CAST(NULLIF(canal_reprocessamento, '') AS STRING) AS reprocessing_channel,
    CAST(NULLIF(versao_do_reprocessamento, '') AS STRING) AS reprocessing_version,
    CAST(NULLIF(sales_company,'') AS STRING) AS sales_company,
    CAST(NULLIF(data_mailing, '') AS DATE) AS dt_mailing,
    CAST(NULLIF(dt_prospect, '') AS DATE) AS dt_prospect,
    CAST(NULLIF(dt_qualified, '') AS DATE) AS dt_qualified,
    CAST(NULLIF(dt_availalable_qualified, '') AS DATE) AS dt_availalable_qualified,
    CAST(NULLIF(dt_opp, '') AS DATE) AS dt_opportunity,
    CAST(NULLIF(dt_first_listing, '') AS DATE) AS dt_first_listing
FROM
    datalake_gsheets_raw.supply_listing_historical_reprocessing_2023