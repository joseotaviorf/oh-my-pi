SELECT
    id,
    guarantee_id AS id_guarantee,
    checkout_order_id AS id_checkout_order,
    cancellation_reason,
    card_token,
    emv,
    installments,
    pix_link,
    qr_code,
    status AS charge_status,
    type AS charge_type,
    refund_amount,
    external_source,
    checkout_order_hash,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_raw.charge
