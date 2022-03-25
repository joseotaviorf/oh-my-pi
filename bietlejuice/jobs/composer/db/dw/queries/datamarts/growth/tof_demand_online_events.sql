WITH
last_version_listings AS (
	SELECT
		id_house,
		sk_house_listing,
		CAST(NULLIF(CAST(ts_listing_version_start as varchar), '') AS timestamp) AS ts_listing_version_start,
		CAST(NULLIF(CAST(ts_listing_version_end as varchar), '') AS timestamp) AS ts_listing_version_end
	FROM
		datalake_clean.ods_dim_house_listing
	WHERE
		CAST(NULLIF(CAST(version AS varchar), '') AS bigint) > 0
)
SELECT
	DATE_TRUNC('week', DATE(ts_event)) AS event_week,
	DATE(ts_event) AS event_date,
	ts_event AS event_timestamp,
	ev.id_user,
	ev.id_amplitude,
	TRIM(JSON_EXTRACT_SCALAR(event_properties, '$["house_id"]')) AS house_id,
	lvl.sk_house_listing,
	JSON_EXTRACT_SCALAR(event_properties, '$.agent_id') AS agent_id,
	CASE WHEN TRIM(event_type) = 'listing_page_viewed' THEN 1 ELSE 0 END AS listing_page_viewed,
	CASE WHEN TRIM(event_type) = 'pilot_cw_button_clicked' THEN 1 ELSE 0 END AS talk_to_agent_button_clicked,
	CASE WHEN TRIM(event_type) = 'piloto_cw_dialog_viewed' THEN 1 ELSE 0 END AS talk_to_agent_dialog_viewed,
	CASE WHEN TRIM(event_type) = 'piloto_cw_message_sent' THEN 1 ELSE 0 END AS talk_to_agent_message_sent,
	CASE WHEN TRIM(event_type) = 'piloto_cw_message_sent' THEN SUBSTR(REGEXP_EXTRACT(REPLACE(REGEXP_REPLACE(JSON_EXTRACT_SCALAR(event_properties, '$["message_content"]'),'\n',' '),'''',' '),'(?<=(([0-9]{9}))).*'),4) ELSE NULL END AS talk_to_agent_message_content,
	CASE WHEN TRIM(event_type) = 'offer_submitted' THEN 1 ELSE 0 END AS offer_submitted,
	CAST(JSON_EXTRACT_SCALAR(user_properties, '$.utm_source') AS varchar) AS utm_source,
	CAST(JSON_EXTRACT_SCALAR(user_properties, '$.utm_medium') AS varchar) AS utm_medium,
	CAST(JSON_EXTRACT_SCALAR(user_properties, '$.utm_campaign') AS varchar) AS utm_campaign,
	CAST(JSON_EXTRACT_SCALAR(user_properties, '$.utm_content') AS varchar) AS utm_content,
	CAST(JSON_EXTRACT_SCALAR(user_properties, '$.utm_term') AS varchar) AS utm_term,
	NOW() AS ts_load
FROM
	datalake_amplitude_clean_prod.events AS ev
LEFT JOIN
	last_version_listings AS lvl
	ON TRIM(JSON_EXTRACT_SCALAR(ev.event_properties, '$["house_id"]'))  = CAST(lvl.id_house AS varchar)
	AND ts_event BETWEEN ts_listing_version_start
	AND (COALESCE(ts_listing_version_end, CURRENT_TIMESTAMP) - INTERVAL '1' SECOND)
WHERE
	DATE(ts_event) >= CURRENT_DATE - INTERVAL '45' DAY
	AND TRIM(event_type) IN (
		'listing_page_viewed',
		'pilot_cw_button_clicked',
		'piloto_cw_dialog_viewed',
		'piloto_cw_message_sent',
		'offer_submitted'
	)
