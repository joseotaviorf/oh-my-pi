SELECT
    id,
    income_id AS id_income,
    status,
    gateway_response,
    amount,
    due_date AS dt_due,
    created_at AS ts_created
FROM
    datalake_monopoly_raw.income_status_log