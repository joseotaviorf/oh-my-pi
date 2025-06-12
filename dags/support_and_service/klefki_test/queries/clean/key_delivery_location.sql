SELECT
	id,
	contract_id as id_contract,
	property_id as id_property,
	user_id as id_user,
	location,
	responsible_person_name,
	responsible_person_phone,
	created_at as ts_created,
	updated_at as ts_updated,
	year,
	month,
	day
FROM
	datalake_klefki_test_raw.key_delivery_location