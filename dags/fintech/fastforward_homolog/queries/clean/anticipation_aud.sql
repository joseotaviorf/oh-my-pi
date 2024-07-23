SELECT
    id,
    invoice_id as id_invoice,
    contract_id as id_contract,
    promo_fee_id as id_promo_fee,
    rev,
    revend as rev_end,
    fee,
    amount,
    status,
    reference_month as dt_reference,
    expires_at as dt_expiration,
    accepted_at as ts_accepted,
    paid_at as ts_paid
FROM
    datalake_fastforward_homolog_raw.anticipation_aud
