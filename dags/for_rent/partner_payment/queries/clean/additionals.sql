SELECT
    id,
    operation_payment_id AS id_operation_payment,
    version,
    additional_type,
    quantity,
    amount,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_partner_payment_raw.additionals