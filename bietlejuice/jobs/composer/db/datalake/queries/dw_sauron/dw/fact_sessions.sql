-- workaround to remove 15 channel duplicates for sessions
WITH last_session_channel AS (
	SELECT
		id_source AS id_session,
		MAX(c.id_channel) AS id_channel
	FROM datalake_quinto_messenger.channel c
	GROUP BY 1
),
customer_identification AS (
	SELECT
		REGEXP_REPLACE(customer_contact,'(^(\\+55)|\\D)','') AS formatted_phone,
		MAX(cpf) AS cpf
	FROM datalake_ebdb_customer_contact_identification.customer_contact_identification
	WHERE channel = 'phone'
	GROUP BY 1
)
SELECT
	s.id_session AS sk_session,
	COALESCE(c.id_conversation,-1) AS sk_conversation,
	COALESCE(s.id_user,-1) AS sk_user,
	ci.cpf AS sk_personal_document,
	COALESCE(CAST(date_format(s.ts_created, 'yyyyMMdd') AS BIGINT), -1) AS sk_created_date,
	c.id_source IS NULL AS is_retained_by_bot,
	s.seconds_duration/60.0 AS minutes_duration,
	NOW() AS ts_load
FROM datalake_sauron.session s
LEFT JOIN last_session_channel lsc
	ON s.id_session = CAST(lsc.id_session AS bigint)
LEFT JOIN datalake_quinto_messenger.channel c
	ON lsc.id_channel = c.id_channel
LEFT JOIN customer_identification ci
	ON ci.formatted_phone = s.customer_phone_formatted
