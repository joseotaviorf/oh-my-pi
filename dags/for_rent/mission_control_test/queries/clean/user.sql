SELECT
	id AS id_user,
	name AS full_name,
	phone AS phone_number,
	deleted AS is_deleted,
	created_on AS ts_created,
	updated_on AS ts_updated,
	year,
	month,
	day
FROM
	datalake_mission_control_test_raw.user
