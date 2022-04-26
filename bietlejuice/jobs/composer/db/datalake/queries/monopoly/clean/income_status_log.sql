SELECT
    id,
    income_id AS id_income,
    status,
    gateway_response,
    amount,
    expiration_date AS dt_expiration,
    due_date AS dt_due,
    occurrence_date AS ts_occurrence,
    created_at AS ts_created
FROM
    datalake_monopoly_raw.income_status_log