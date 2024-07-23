SELECT
    id,
    contract_id as id_contract,
    promo_fee_id as id_promo_fee,
    rev,
    revtype as rev_type,
    reference_month as dt_reference
FROM
    datalake_fastforward_homolog_raw.anticipation_promo_for_contract_aud
