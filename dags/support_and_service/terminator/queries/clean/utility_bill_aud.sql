SELECT
    id,
    termination_id AS id_termination,
    external_id AS id_external,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    type,
    status,
    attachments_last_invoice,
    attachments_payment_voucher,
    is_included_condominium,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_terminator_raw.utility_bill_aud
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
