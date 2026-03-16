SELECT
	id,
	recurrence_phase_id AS id_recurrence_phase,
	status,
	accrual AS dt_accrual,
	open_date AS dt_open,
	close_date AS dt_close,
	created_at AS ts_created,
	updated_at AS ts_updated
FROM
	datalake_billing_raw.recurrence_phase_control
-- This filter ensures that only records created after the billing cleanup are considered.
WHERE created_at > '2026-01-21'
