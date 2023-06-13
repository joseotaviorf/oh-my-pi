SELECT
    id,
    external_offer_id AS id_external_offer,
    revision,
    ledger_rule,
    down_payment_amount,
    entry_payment_amount,
    financed_amount,
    total_payment_amount,
    payment_method,
    brokerage_fee,
    payment_allowed_at AS ts_payment_allowed,
    event_date_time AS ts_event,
    created_at AS ts_created
FROM
    datalake_monopoly_raw.sale_revision