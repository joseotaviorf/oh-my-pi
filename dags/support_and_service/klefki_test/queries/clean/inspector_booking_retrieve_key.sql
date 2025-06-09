SELECT
	id AS id_inspector_booking_retrieve_key,
	inspector_id AS id_inspector,
	house_id AS id_house,
	collect_day,
	collect_hour,
	zipcode,
	street,
	CAST(number AS INT) AS number,
	complement,
	district,
	city,
	state,
	instructions,
	created_at as ts_created,
	updated_at as ts_updated,
	year,
	month,
	day
FROM
	datalake_klefki_test_raw.inspector_booking_retrieve_key
