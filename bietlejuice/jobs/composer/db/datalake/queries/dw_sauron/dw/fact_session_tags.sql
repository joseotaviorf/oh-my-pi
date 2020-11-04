SELECT
	id AS sk_session,
	EXPLODE(context) AS tag
FROM datalake_sauron.session
