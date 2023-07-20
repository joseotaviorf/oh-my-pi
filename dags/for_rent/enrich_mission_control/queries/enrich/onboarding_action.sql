SELECT
	id,
	id_onboarding,
	type_identifier,
	user_role_target_type,
	is_deleted,
	ts_created,
	ts_updated
FROM
	datalake_mission_control_clean.onboarding_action
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) = 1