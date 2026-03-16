SELECT
	id,
	recurrence_id AS id_recurrence,
	revision ,
	currency,
	min_number_of_days_to_pay,
	type_of_min_number_days_to_pay,
	metadata,
	start_charge_date AS dt_start_charge,
	created_at AS ts_createed
FROM
	datalake_billing_raw.recurrence_revision
-- This filter ensures that only records created after the billing cleanup are considered.
WHERE created_at > '2026-01-21'
