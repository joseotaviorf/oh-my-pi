WITH phone_users_number AS (
    SELECT
        dc.from_phone_number,
        dc.ts_started AS dt_interaction
    FROM
        call.dim_call dc
    WHERE
        dc.to_phone_number in ('+5511933058701', '+5531933007908', '+5540202507')
    GROUP BY 1,2 
), 
chat_users_number AS (
    SELECT
        dc.customer_phone,
        dc.ts_created AS dt_interaction
    FROM
        quinto_messenger.dim_task dt
    JOIN quinto_messenger.fact_tasks ft
        USING(sk_task)
    JOIN quinto_messenger.dim_chat dc
        USING(sk_chat)
    WHERE
        dt.department ILIKE '%plaquinhas%'
    GROUP BY 1,2
),
all_users AS (
-------------------
-- QR Code users --
-------------------
    SELECT
    	e.id_user::BIGINT AS sk_user,
    	true AS is_qr_code_user,
    	NULL::BOOL AS is_phone_user,
    	NULL::BOOL AS is_chat_user,
    	CAST(e.ts_event AS DATE) AS dt_interaction
    FROM 
    	datalake_amplitude_clean_prod.events e
    WHERE
    	e.id_app = 170698
    	AND e.year = 2021
    	AND CAST(JSON_EXTRACT_PATH_TEXT(e.user_properties, 'utm_source') AS VARCHAR) LIKE '%plaquinhas%'
    	AND COALESCE(e.id_user,'') <> ''
    	AND CAST(e.ts_event AS DATE) >= '2021-02-19'
    UNION ALL
------------------
-- Phone users --
------------------
    SELECT
    	sk_user AS sk_user,
    	NULL::BOOL AS is_qr_code_user,
    	true AS is_phone_user,
    	NULL::BOOL AS is_chat_user,
    	dt_interaction
    FROM
    	public.dim_user
    JOIN phone_users_number
        ON phone_users_number.from_phone_number = public.dim_user.telefone_principal
    UNION ALL
------------------
-- Chat users --
------------------
    SELECT
    	sk_user,
    	NULL::BOOL AS is_qr_code_user,
    	NULL::BOOL AS is_phone_user,
    	true AS is_chat_user,
    	dt_interaction
    FROM
    	public.dim_user 
    JOIN chat_users_number
        ON chat_users_number.customer_phone = public.dim_user.telefone_principal
	UNION ALL
--------------
-- CX users --
--------------
    SELECT
    	(case when id_user ~ '^[0-9]+$' then id_user else null end)::BIGINT AS sk_user,
    	NULL::BOOL AS is_qr_code_user,
    	CASE WHEN canal = 'Telefone' THEN true ELSE NULL END AS is_phone_user,
    	CASE WHEN canal = 'Chat' THEN true ELSE NULL END AS is_chat_user,
    	data_hora::DATE AS dt_interaction 
    FROM
    	datalake_raw.gsheets_users_cx_plaquinhas
)
SELECT 
    sk_user AS sk_client,
    BOOL_OR(is_qr_code_user) AS is_qr_code_user,
    BOOL_OR(is_phone_user) AS is_phone_user,
    BOOL_OR(is_chat_user) AS is_chat_user,
    min(dt_interaction::DATE) AS dt_first_interaction,
    max(dt_interaction::DATE) AS dt_last_interaction    
FROM
    all_users 
WHERE
    sk_user > 0
GROUP BY 1