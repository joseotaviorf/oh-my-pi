SELECT
	id as id_address_location_key,
	zipcode,
	street,
	number,
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
	datalake_klefki_raw.address_location_key
WHERE
	year = {year}
	AND month = {month}
	AND day = {day}
