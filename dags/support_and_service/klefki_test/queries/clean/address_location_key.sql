SELECT
	id as id_address_location_key,
	zipcode,
	street,
	CAST(number AS INT) AS number,
	complement,
	district,
	city,
	state,
	instructions,
	created_at AS ts_created,
	updated_at AS ts_updated,
	year,
	month,
	day
FROM
	datalake_klefki_test_raw.address_location_key
