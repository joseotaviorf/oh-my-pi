SELECT
    id,
    external_order_id as id_external_order,
    advance_payment_id as id_advance_payment,
    external_charge_id as id_external_charge,
    rev,
    revend,
    revtype,
    status,
    installments,
    payment_amount,
    unique_hash,
    paid_at_mod as mod_ts_paid,
    status_mod as mod_status,
    payment_method_mod as mod_payment_method,
    installments_mod as mod_installments,
    payment_amount_mod as mod_payment_amount,
    created_at as ts_created,
    updated_at as ts_updated,
    paid_at as ts_paid
FROM
    datalake_rental_transact_raw.advance_payment_order_aud
