SELECT
    id,
    external_invoice_id AS id_external_invoice,
    installment_uuid AS uuid_installment,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    accrual_year_month,
    status,
    type,
    amount,
    installment_uuid_mod AS mod_uuid_installment,
    external_invoice_id_mod AS mod_id_external_invoice,
    accrual_year_month_mod AS mod_accrual_year_month,    
    status_mod AS mod_status,
    type_mod AS mod_type,
    amount_mod AS mod_amount,
    created_at_mod AS mod_ts_created,
    updated_at_mod AS mod_ts_updated,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.installment_aud

WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
