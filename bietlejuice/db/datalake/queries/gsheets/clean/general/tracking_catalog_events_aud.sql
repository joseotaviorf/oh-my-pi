SELECT
	CAST(NULLIF(REPLACE(id_app, ',', ''), '') AS INT) AS id_app,
	NULLIF(category, '') AS category,
	NULLIF(event_type, '') AS event_type,
	NULLIF(business_owner, '') AS business_owner,
	NULLIF(technical_owner, '') AS technical_owner,
	NULLIF(squad_ownership, '') AS squad_ownership,
	NULLIF(platform, '') AS platform,
	NULLIF(project_name, '') AS project_name,
	NULLIF(screen_image_link, '') AS screen_image_link,
	NULLIF(status, '') AS status,
	NULLIF(emitting_app, '') AS emitting_app,
	NULLIF(rev_type, '') AS rev_type,
	NULLIF(rev_user, '') AS rev_user,
	NULLIF(description, '') AS description,
	CAST(NULLIF(is_key_event, '') AS BOOLEAN) AS is_key_event,
	FROM_UNIXTIME(CAST(NULLIF(rev_timestamp, '') AS BIGINT)/1000) AS ts_rev, -- this timestamp is in milliseconds
	TO_DATE(REPLACE(first_seen, '/', '-'), 'M-d-y') AS first_seen,
	TO_DATE(REPLACE(last_seen, '/', '-'), 'M-d-y') AS last_seen
FROM
    datalake_gsheets_raw.events_aud;
