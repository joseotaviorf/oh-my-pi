SELECT
    id_offer,
    payment_model,
    COALESCE(TRY_CAST(REPLACE(sale_price_agreed, ',', '.') AS FLOAT), 0) AS sale_price_agreed,
    COALESCE(TRY_CAST(REPLACE(brokerage_fee, ',', '.') AS FLOAT), 0) AS brokerage_fee,
    COALESCE(TRY_CAST(REPLACE(brokerage_amount, ',', '.') AS FLOAT), 0) AS brokerage_amount,
    COALESCE(TRY_CAST(REPLACE(brokerage_quinto_andar_ciq_amount, ',', '.') AS FLOAT), 0) AS brokerage_quinto_andar_ciq_amount,
    COALESCE(TRY_CAST(REPLACE(brokerage_quinto_andar_amount, ',', '.') AS FLOAT), 0) AS brokerage_quinto_andar_amount,
    COALESCE(
        TO_DATE(dt_signed_ccv, 'yyyy-MM-dd HH:mm:ss'),
        TO_DATE(dt_signed_ccv, 'yyyy-MM-dd')
    ) AS dt_signed_ccv,
    COALESCE(
        TO_DATE(dt_legal_analysis_marketplace, 'yyyy-MM-dd HH:mm:ss'),
        TO_DATE(dt_legal_analysis_marketplace, 'yyyy-MM-dd')
    ) AS dt_legal_analysis_marketplace
FROM
    datalake_gsheets_raw.marketplace_rede_ops_exceptions
WHERE
    id_offer IS NOT NULL
    and id_offer != '-'
