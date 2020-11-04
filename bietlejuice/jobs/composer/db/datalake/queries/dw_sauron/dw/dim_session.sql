SELECT
	id_session AS sk_session,
	source_environment AS source,
	agent AS attendance,
	department AS department_name,
	customer_phone_formatted AS customer_phone,
	customer_type,
	customer_flow_step AS flow_step,
	status,
	ts_created,
	ts_first_message,
	ts_updated
FROM datalake_sauron.session
