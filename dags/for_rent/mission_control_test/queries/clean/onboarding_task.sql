SELECT
	id,
	onboarding_id AS id_onboarding,
	task_type_id AS id_task_type,
	reference_date_field,
	title,
	status,
	start_offset,
	end_offset,
	CAST(deleted AS BOOLEAN) AS id_deleted,
	DATE(start_date) AS dt_started,
	DATE(due_date) AS dt_due,
	created_on AS ts_created,
	updated_on AS ts_updated,
	year,
	month,
	day
FROM
	datalake_mission_control_test_raw.onboardingtask
