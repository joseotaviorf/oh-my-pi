SELECT
    id,
    termination_id AS id_termination,
    external_id AS id_external,
    type,
    status,
    attachments_last_invoice,
    attachments_payment_voucher,
    is_included_condominium,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_terminator_raw.utility_bill
