SELECT
	id AS id_session,
	GET_JSON_OBJECT(user_data, '$.user_id') AS id_user,
	user_phone AS customer_phone,
	REGEXP_REPLACE(user_phone,'(^(\\+?55)|\\D)','') AS customer_phone_formatted, -- include DDI code with '+' only if number is outside of Brazil
	agent,
	source_environment,
	department,
	status,
	LOWER(GET_JSON_OBJECT(user_data, '$.type')) AS customer_type,
	LOWER(GET_JSON_OBJECT(user_data, '$.flowstep')) AS customer_flow_step,
	context AS customer_tags,
	UNIX_TIMESTAMP(ts_last_message) - UNIX_TIMESTAMP(ts_first_message) AS seconds_duration,
	ts_created,
	ts_first_message,
	ts_last_message,
	ts_updated
FROM datalake_sauron_clean.session