SELECT
    id,
    external_order_id as id_external_order,
    advance_payment_id as id_advance_payment,
    external_charge_id as id_external_charge,
    status,
    installments,
    payment_amount,
    unique_hash,
    created_at as ts_created,
    updated_at as ts_updated,
    paid_at as ts_paid
FROM
    datalake_rental_transact_raw.advance_payment_order
