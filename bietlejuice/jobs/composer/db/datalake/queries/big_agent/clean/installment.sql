SELECT
    id,
    external_invoice_id AS id_external_invoice,
    installment_uuid AS uuid_installment,
    accrual_year_month,
    status,
    type,
    amount,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.installment
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
