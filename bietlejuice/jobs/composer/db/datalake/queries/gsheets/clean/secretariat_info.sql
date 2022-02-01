SELECT
	CAST(sk_user_secretary AS BIGINT) AS sk_user_secretary,
	CAST(id_secretary AS BIGINT) AS id_secretary,
	secretary_email,
	secretary_name,
	type,
	DATE(dt_ended) AS dt_ended,
	DATE(dt_started) AS dt_started
FROM
    datalake_gsheets_raw.secretary_info