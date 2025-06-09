SELECT
	id AS id_lock_box_track_entries,
	lock_box_id AS id_lock_box,
	house_id AS id_house,
	user_id AS id_user,
	user_email,
	user_role,
	`password`,
	created_at as ts_created,
	updated_at as ts_updated,
    year,
    month,
    day
FROM
	datalake_klefki_test_raw.lock_box_track_entries