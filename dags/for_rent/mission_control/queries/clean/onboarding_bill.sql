SELECT
	id,
	onboarding_id AS id_onboarding,
	address_id AS id_address,
	supplier_id AS id_supplier,
	supplier_city_id AS id_supplier_city,
	google_drive_id AS id_google_drive,
	google_drive_file_id AS id_google_drive_file,
	status,
	type,
	ownership,
	ownership_cpf,
	installation_code,
	total_debit,
	CAST(is_on AS BOOLEAN) AS is_on,
	CAST(is_active AS BOOLEAN) AS is_active,
	CAST(deleted AS BOOLEAN) AS is_deleted,
	created_on AS ts_created,
	updated_on AS ts_updated,
	year,
	month,
	day
FROM
	datalake_mission_control_raw.onboardingbill
