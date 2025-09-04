SELECT
	id, 
	recurrence_phase_id AS id_recurrence_phase,
	revision,
	period,
	index,
	status,
	status_reason,
	metadata,
	start_charge AS dt_start_charge,
	end_charge AS dt_end_charge,
	open_date AS dt_open,
	close_date AS dt_close,
	created_at AS ts_created
FROM 
	datalake_billing_raw.recurrence_phase_revision
