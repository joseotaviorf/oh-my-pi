SELECT
	CAST(id AS BIGINT) AS id,
	CAST(user_id AS BIGINT) AS id_user,
	CAST(event_id AS BIGINT) AS id_event,
	entity_id AS id_entity,
	entity_name,
	action,
	status,
	channel,
	tags,
	destination,
	template,
	country AS country_code,
	ccost AS cost_center,
	scope,
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