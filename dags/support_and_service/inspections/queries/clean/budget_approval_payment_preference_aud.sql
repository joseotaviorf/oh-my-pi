SELECT
    id AS id_budget_approval_payment_preference,
    budget_id AS id_budget,
    inspection_id AS id_inspection,
    reviewer_id AS id_reviewer,
    type,
    type_mod AS mod_type,
    installments,
    installments_mod AS mod_installments,
    total,
    total_mod AS mod_total,
    revtype AS rev_type,
    rev,
    revend AS rev_end,
    created_at AS ts_created,
    created_at_mod AS mod_ts_created,
    updated_at AS ts_updated,
    updated_at_mod AS mod_ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.budget_approval_payment_preference_aud
WHERE
	MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
