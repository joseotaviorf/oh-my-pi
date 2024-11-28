SELECT
	id,
	user_type,
	type,
	CAST(active AS BOOLEAN) AS is_active,
	created_on AS ts_created,
	updated_on AS ts_updated,
	year,
	month,
	day
FROM
	datalake_mission_control_raw.onboardingtasktypes
