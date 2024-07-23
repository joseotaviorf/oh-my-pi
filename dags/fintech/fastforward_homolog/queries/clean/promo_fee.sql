SELECT
    id,
    fee,
    title,
    description,
    created_at as ts_created,
    updated_at as ts_updated
FROM
    datalake_fastforward_homolog_raw.promo_fee
