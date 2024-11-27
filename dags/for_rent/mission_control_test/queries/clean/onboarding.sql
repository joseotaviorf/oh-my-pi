SELECT
	id,
	contract_id AS id_contract,
	google_drive_id AS id_google_drive,
	status,
	property_type,
	key_location,
	key_location_details,
	version,
	CAST(deleted AS BOOLEAN) AS is_deleted,
	created_on AS ts_created,
	updated_on AS ts_updated,
	last_sync AS ts_last_synced,
	year,
	month,
	day
FROM
	datalake_mission_control_test_raw.onboarding
