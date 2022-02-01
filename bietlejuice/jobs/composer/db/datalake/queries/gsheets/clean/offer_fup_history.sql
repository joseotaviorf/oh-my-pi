SELECT
	CAST(sk_user_lead AS BIGINT) AS sk_user_lead,
	CAST(sk_user_secretary AS BIGINT) AS sk_user_secretary,
	CAST(id_secretary AS BIGINT) AS id_secretary,
	lead_email,
	lead_name,
	lead_phone_number,
	lead_secretary_type,
	secretary_email,
	DATE(dt_contact) AS dt_contact
FROM
    datalake_gsheets_raw.offer_fup_history