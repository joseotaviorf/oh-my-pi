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
    	AND e.year >= 2021
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
),
plaquinhas_users AS (
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
),
metrics_base AS (
    SELECT
        u.sk_client,
        sk_house_listing,
        id_house,
        sk_booking,
        sk_offer,
        sk_proposal,
        sk_contract,
        sk_rf,
        city_group,
        flow_event,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        utm_campaign,
        utm_term,
        utm_content,
        campaign_name,
        status,
        is_qr_code_user,
        is_phone_user,
        is_chat_user,
        rent_flow_order,
        tenant_prospect_order,
        dt_first_interaction,
        dt_last_interaction,
        dt_event,
        dt_booking_created,
        flg_visit_completed,
        dt_offer_submitted,
        dt_offer_approved,
        dt_tenant_first_doc_sent,
        dt_credit_analysis_approved,
        dt_contract_signed,
        NULL::FLOAT AS visits_booked_target
    FROM 
        plaquinhas_users u
    LEFT JOIN datamarts.performance_marketing_metrics_demand pmmd 
        ON u.sk_client = pmmd.sk_client AND pmmd.dt_event BETWEEN u.dt_first_interaction AND dateadd(day, 90, u.dt_last_interaction)
),
targets AS (
    SELECT
        NULL::INT AS sk_client,
        NULL::INT AS sk_house_listing,
        NULL::INT AS id_house,
        NULL::INT AS sk_booking,
        NULL::INT AS sk_offer,
        NULL::INT AS sk_proposal,
        NULL::INT AS sk_contract,
        NULL AS sk_rf,
        NULL::TEXT AS city_group,
        NULL::TEXT AS flow_event,
        NULL::TEXT AS mkt_origin,
        NULL::TEXT AS mkt_channel,
        NULL::TEXT AS mkt_medium,
        NULL::TEXT AS mkt_source,
        NULL::TEXT AS utm_campaign,
        NULL::TEXT AS utm_term,
        NULL::TEXT AS utm_content,
        NULL::TEXT AS campaign_name,
        NULL::TEXT AS status,
        CASE WHEN tgt.channel = 'QR Code' THEN TRUE else FALSE END AS is_qr_code_user,
        CASE WHEN tgt.channel = 'Phone' THEN TRUE else FALSE END AS is_phone_user,
        NULL::BOOL AS is_chat_user,
        NULL::INT AS rent_flow_order,
        NULL::INT AS tenant_prospect_order,
        NULL::DATE AS dt_first_interaction,
        NULL::DATE AS dt_last_interaction,
        NULL::DATE AS dt_event,
        tgt.dt_target AS dt_booking_created,
        NULL::BOOL AS flg_visit_completed,
        NULL::DATE AS dt_offer_submitted,
        NULL::DATE AS dt_offer_approved,
        NULL::DATE AS dt_tenant_first_doc_sent,
        NULL::DATE AS dt_credit_analysis_approved,
        NULL::DATE AS dt_contract_signed,
        tgt.visits_booked_target
    FROM 
        datalake_gsheets_clean_prod.plaquinhas_demand_targets tgt
)
-------------------------------
-- UNION results and targets --
-------------------------------
SELECT 
    mb.*
FROM 
    metrics_base mb
UNION ALL
SELECT 
    t.*
FROM 
    targets t