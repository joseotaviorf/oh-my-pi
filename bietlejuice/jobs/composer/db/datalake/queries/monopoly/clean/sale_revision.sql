SELECT
    id,
    external_offer_id AS id_external_offer,
    revision,
    ledger_rule,
    down_payment_amount,
    entry_payment_amount,
    fgts_amount_preview
FROM
    datalake_monopoly_raw.sale_revision