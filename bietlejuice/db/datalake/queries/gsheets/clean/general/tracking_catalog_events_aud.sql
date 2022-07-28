SELECT
	CAST(NULLIF(REPLACE(id_app, ',', ''), '') AS INT) AS id_app,
	NULLIF(category, '') AS category,
	NULLIF(event_type, '') AS event_type,
	NULLIF(owner, '') AS owner,
	NULLIF(platform, '') AS platform,
	NULLIF(project_name, '') AS project_name,
	NULLIF(status, '') AS status,
	NULLIF(rev_type, '') AS rev_type,
	NULLIF(rev_user, '') AS rev_user,
	NULLIF(description, '') AS description,
    FROM_UNIXTIME(CAST(NULLIF(rev_timestamp, '') AS BIGINT)/1000) AS ts_rev, -- this timestamp is in milliseconds
	TO_DATE(REPLACE(first_seen, '/', '-'), 'M-d-y') AS first_seen,
        TO_DATE(REPLACE(last_seen, '/', '-'), 'M-d-y') AS last_seen
FROM
    datalake_gsheets_raw.events_aud;
