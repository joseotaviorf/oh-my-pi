SELECT 
	id,
	id_contract,
	id_google_drive,
	status,
	property_type,
	key_location,
	key_location_details,
	version,
	is_deleted,
	ts_created,
	ts_updated,
	ts_last_synced
FROM 
  datalake_mission_control_clean.onboarding
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) = 1