SELECT
    id,
    guarantee_id AS id_guarantee,
    cancellation_reason,
    card_token,
    emv,
    installments,
    pix_link,
    qr_code,
    status AS charge_status,
    type AS charge_type,
    refund_amount,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_raw.charge
