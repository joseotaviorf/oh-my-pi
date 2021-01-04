SELECT
    id,
    payee_id as id_payee,
    due_amount,
    accounting_year_month,
    created_at as ts_created,
    disabled_at as ts_disabled,
    blocked_at as ts_blocked
FROM
    datalake_robin_hood_raw.tax