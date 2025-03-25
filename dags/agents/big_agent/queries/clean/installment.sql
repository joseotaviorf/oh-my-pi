SELECT
    id,
    external_invoice_id AS id_external_invoice,
    earning_id AS id_earning,
    CAST(accounting_external_id AS BIGINT) AS id_accounting_external,
    installment_uuid AS uuid_installment,
    type,
    status,
    amount,
    accrual_year_month,
    send_to_bank_on AS dt_sent_to_bank,
    CAST(accounted_at AS TIMESTAMP) AS ts_accounted,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.Installment