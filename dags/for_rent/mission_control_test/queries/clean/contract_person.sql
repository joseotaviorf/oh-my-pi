SELECT
	id,
	contract_id AS id_contract,
	address_id AS id_address,
	user_id AS id_user,
	contract_type,
	type AS person_type,
	name AS full_name,
	phone_number,
	document_number,
	deleted AS is_deleted,
	created_on AS ts_created,
	updated_on AS ts_updated,
    year,
	month,
	day
FROM
	datalake_mission_control_test_raw.contractperson
