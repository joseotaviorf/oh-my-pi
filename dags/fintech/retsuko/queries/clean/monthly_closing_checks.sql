SELECT
    id,
    external_id AS id_external,
    contract_id AS id_contract,
    cdc_transaction_id,
    checks,
    accrual_year_month,
    type,
    timestamp(created_at) AS ts_created,
    timestamp(updated_at) AS ts_updated
FROM
    datalake_retsuko_raw.monthly_closing_checks
