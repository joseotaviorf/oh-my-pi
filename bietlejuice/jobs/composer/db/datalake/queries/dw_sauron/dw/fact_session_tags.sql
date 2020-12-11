SELECT
	id_session AS sk_session,
	EXPLODE(customer_tags) AS tags
FROM datalake_sauron.session
