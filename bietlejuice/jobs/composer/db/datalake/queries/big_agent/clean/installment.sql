SELECT
    id,
    external_invoice_id AS id_external_invoice,
    installment_uuid AS uuid_installment,
    type,
    status,
    amount,
    accrual_year_month,
    send_to_bank_on AS dt_sent_to_bank,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.Installment
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
