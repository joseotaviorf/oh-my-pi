SELECT
	CAST(id AS BIGINT) AS id,
	CAST(user_id AS BIGINT) AS id_user,
	CAST(event_id AS BIGINT) AS id_event,
	action,
	status,
	channel,
	tags,
	CAST(sent_at AS TIMESTAMP) AS ts_sent,
	CAST(created_at AS TIMESTAMP) AS ts_created,
	CAST(updated_at AS TIMESTAMP) AS ts_updated,
	year,
	month,
	day
FROM 
	datalake_jaiminho_raw.user_notifications_view
WHERE 
	year = {year}
	AND month = {month}
	AND day = {day}