SELECT
    id AS id_budget_approval_payment_preference,
    budget_id AS id_budget,
    inspection_id AS id_inspection,
    reviewer_id AS id_reviewer,
    type,
    installments,
    total,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.budget_approval_payment_preference
WHERE
	MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
