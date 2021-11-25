SELECT
    id,
    external_invoice_id AS id_external_invoice,
    installment_uuid AS uuid_installment,
    rev,
    type,
    status,
    revtype AS rev_type,
    revend AS rev_end,
    amount,
    accrual_year_month,
    external_invoice_id_mod AS mod_id_external_invoice,
    installment_uuid_mod AS mod_uuid_installment,
    type_mod AS mod_type,
    amount_mod AS mod_amount,
    accrual_year_month_mod AS mod_accrual_year_month,
    status_mod AS mod_status,
    send_to_bank_on_mod AS mod_dt_sent_to_bank,
    created_at_mod AS mod_ts_created,
    updated_at_mod AS mod_ts_updated,
    send_to_bank_on AS dt_sent_to_bank,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.Installment_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
