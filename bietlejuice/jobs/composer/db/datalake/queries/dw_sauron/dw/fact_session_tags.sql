SELECT
	id_session AS sk_session,
	EXPLODE(customer_tags) AS tags,
	NOW() AS ts_load
FROM datalake_sauron.session
