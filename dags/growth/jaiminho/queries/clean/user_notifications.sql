SELECT
	CAST(id AS BIGINT) AS id,
	CAST(userid AS BIGINT) AS id_user,
	CAST(eventId AS BIGINT) AS id_event,
	referenceId AS id_entity,
	referenceName AS entity_name,
	action,
	status,
	channel,
	tags,
	destination,
	payload:bodyTemplate AS template,
	payload:country AS country_code,
	payload:metadata AS metadata,
	ccost AS cost_center,
	scope,
	CAST(sentAt AS TIMESTAMP) AS ts_sent,
	CAST(createdAt AS TIMESTAMP) AS ts_created,
	CAST(updatedAt AS TIMESTAMP) AS ts_updated,
	year,
	month,
	day
FROM
	datalake_jaiminho_raw.user_notifications
