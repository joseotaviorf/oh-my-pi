SELECT
    id as id_promo_fee,
    rev,
    fee,
    title,
    description,
    revtype as rev_type
FROM
    datalake_fastforward_homolog_raw.promo_fee_aud
