SELECT
	id,
	onboarding_id AS id_onboarding,
	type_identifier,
	user_role_type_target AS user_role_target_type,
	CAST(deleted AS BOOLEAN) AS is_deleted,
	created_on AS ts_created,
	updated_on AS ts_updated,
	year,
	month,
	day
FROM
	datalake_mission_control_test_raw.onboardingaction
