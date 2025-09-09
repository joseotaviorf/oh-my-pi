SELECT
	id,
	external_id AS id_external,
	recurrence_phase_revision_id AS id_recurrence_phase_revision,
	status,
	status_reason,
	accrual AS dt_accrual,
	opened_at AS dt_opened,
	closed_at AS dt_closed,
	created_at AS ts_created,
	updated_at AS ts_updated
FROM 
	datalake_billing_raw.recurrence_phase_execution
