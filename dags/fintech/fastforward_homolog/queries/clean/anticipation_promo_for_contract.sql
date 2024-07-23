SELECT
    id,
    contract_id as id_contract,
    promo_fee_id as id_promo_fee,
    reference_month as dt_reference,
    created_at as ts_created,
    updated_at as ts_updated
FROM
    datalake_fastforward_homolog_raw.anticipation_promo_for_contract
