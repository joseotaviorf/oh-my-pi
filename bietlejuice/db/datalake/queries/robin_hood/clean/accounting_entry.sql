SELECT
    id, 
    external_id AS id_external,
    source_id AS id_source,
    payee_id AS id_payee,
    description,
    source_bill_item,
    due_amount,
    locale,
    type,
    cost_center_code,
    accrual_year_month,
    accounting_year_month,
    metadata,
    DATE(occurrence_date) AS dt_occurrence,
    TIMESTAMP(blocked_at) AS ts_blocked,
    TIMESTAMP(created_at) AS ts_created
FROM
    datalake_robin_hood_raw.accounting_entry