SELECT
	id AS id_key_return_preferred_location_aud,
	address_location_key_id AS id_address_location_key,
	property_id AS id_property,
	user_id AS user_id,
	rev,
	revend AS rev_end,
	revtype AS rev_type,
	`location`,
	`source`,
	response_date as ts_response,
	created_at as ts_created,
	updated_at as ts_updated,
    year,
    month,
    day
FROM
	datalake_klefki_test_raw.key_return_preferred_location_aud
