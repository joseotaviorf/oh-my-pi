WITH phone_users_number AS (
    SELECT
        dc.from_phone_number
    FROM
        call.dim_call dc
    WHERE
        dc.to_phone_number in ('+5511933058701', '+5531933007908')
    GROUP BY 1 
), 
chat_users_number AS (
    SELECT
        dc.customer_phone
    FROM
        quinto_messenger.dim_task dt
    JOIN quinto_messenger.fact_tasks ft
        USING(sk_task)
    JOIN quinto_messenger.dim_chat dc
        USING(sk_chat)
    WHERE
        dt.department ILIKE '%plaquinhas%'
    GROUP BY 1
),
all_users AS (
-------------------
-- QR Code users --
-------------------
    SELECT
	e.id_user::BIGINT AS sk_user,
	true AS is_qr_code_user,
	NULL::BOOL AS is_phone_user,
	NULL::BOOL AS is_chat_user
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
	NULL::BOOL AS is_chat_user  	
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
	true AS is_chat_user      	
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
	CASE WHEN canal = 'Chat' THEN true ELSE NULL END AS is_chat_user
    FROM
    	datalake_raw.gsheets_users_cx_plaquinhas
),
user_by_channel AS (
    SELECT 
	sk_user,
	BOOL_OR(is_qr_code_user) AS is_qr_code_user,
	BOOL_OR(is_phone_user) AS is_phone_user,
	BOOL_OR(is_chat_user) AS is_chat_user
    FROM
	all_users 
    WHERE
        sk_user > 0
    GROUP BY 1
),
funnel_counts AS (
    SELECT
	sk_client,
	city_group,
	mkt_origin,
	mkt_channel,
	mkt_medium,
	mkt_source,
	utm_campaign,
	utm_term,
	utm_content,
	COUNT(DISTINCT sk_booking) AS visits_booked,
	COUNT(DISTINCT CASE WHEN flg_visit_completed = TRUE THEN sk_booking ELSE NULL END) AS bookings_confirmed,
	NULL::INT AS offers_submitted,
	NULL::INT AS offers_approved,
	NULL::INT AS documents_first_sent,
	NULL::INT AS credit_approved,
	NULL::INT AS contracts_signed,
	dt_event AS date_event
    FROM
    	datamarts.performance_marketing_metrics_demand
    WHERE
    	dt_event >= '2021-02-19'
    GROUP BY 1,2,3,4,5,6,7,8,9,12,13,14,15,16,17
    UNION ALL
    SELECT
	sk_client,
	city_group,
	mkt_origin,
	mkt_channel,
	mkt_medium,
	mkt_source,
	utm_campaign,
	utm_term,
	utm_content,
	NULL::INT AS visits_booked,
	NULL::INT AS bookings_confirmed,
	COUNT(DISTINCT CASE WHEN dt_offer_submitted>0 THEN sk_offer ELSE NULL END) AS offers_submitted,
	NULL::INT AS offers_approved,
	NULL::INT AS documents_first_sent,
	NULL::INT AS credit_approved,
	NULL::INT AS contracts_signed,
	dt_offer_submitted AS date_event
    FROM
	datamarts.performance_marketing_metrics_demand
    WHERE
	date_event >= '2021-02-19'
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,13,14,15,16,17
    UNION ALL
    SELECT
	sk_client,
	city_group,
	mkt_origin,
	mkt_channel,
	mkt_medium,
	mkt_source,
	utm_campaign,
	utm_term,
	utm_content,
	NULL::INT AS visits_booked,
	NULL::INT AS bookings_confirmed,
	NULL::INT AS offers_submitted,
	COUNT(DISTINCT CASE WHEN dt_offer_approved>0 THEN sk_offer ELSE NULL END) AS offers_approved,
	NULL::INT AS documents_first_sent,
	NULL::INT AS credit_approved,
	NULL::INT AS contracts_signed,
	dt_offer_approved AS date_event
    FROM
	datamarts.performance_marketing_metrics_demand
    WHERE
	date_event >= '2021-02-19'
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,14,15,16,17
    UNION ALL
    SELECT
	sk_client,
	city_group,
	mkt_origin,
	mkt_channel,
	mkt_medium,
	mkt_source,
	utm_campaign,
	utm_term,
	utm_content,
	NULL::INT AS visits_booked,
	NULL::INT AS bookings_confirmed,
	NULL::INT AS offers_submitted,
	NULL::INT AS offers_approved,
	COUNT(DISTINCT CASE WHEN dt_tenant_first_doc_sent>0 THEN sk_proposal ELSE NULL END) AS documents_first_sent,
	NULL::INT AS credit_approved,
	NULL::INT AS contracts_signed,
	dt_tenant_first_doc_sent AS date_event
    FROM
	datamarts.performance_marketing_metrics_demand
    WHERE
	date_event >= '2021-02-19'
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,15,16,17
    UNION ALL
    SELECT
	sk_client,
	city_group,
	mkt_origin,
	mkt_channel,
	mkt_medium,
	mkt_source,
	utm_campaign,
	utm_term,
	utm_content,
	NULL::INT AS visits_booked,
	NULL::INT AS bookings_confirmed,
	NULL::INT AS offers_submitted,
	NULL::INT AS offers_approved,
	NULL::INT AS documents_first_sent,
	COUNT(DISTINCT CASE WHEN dt_credit_analysis_approved>0 THEN sk_proposal ELSE NULL END) AS credit_approved,
	NULL::INT AS contracts_signed,
	dt_credit_analysis_approved AS date_event
    FROM
	datamarts.performance_marketing_metrics_demand
    WHERE
	date_event >= '2021-02-19'
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,16,17
    UNION ALL
    SELECT
	sk_client,
	city_group,
	mkt_origin,
	mkt_channel,
	mkt_medium,
	mkt_source,
	utm_campaign,
	utm_term,
	utm_content,
	NULL::INT AS visits_booked,
	NULL::INT AS bookings_confirmed,
	NULL::INT AS offers_submitted,
	NULL::INT AS offers_approved,
	NULL::INT AS documents_first_sent,
	NULL::INT AS credit_approved,
	COUNT(DISTINCT CASE WHEN dt_contract_signed>0 THEN sk_contract ELSE NULL END) AS contracts_signed,
	dt_contract_signed AS date_event
    FROM
	datamarts.performance_marketing_metrics_demand
    WHERE
	date_event >= '2021-02-19'
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,17
),
--------------------------------------
-- Plaquinhas installation control  --
--------------------------------------
plaquinhas AS (
    SELECT
        p.id_house::BIGINT AS id_house,
        dr.city_group,
        date::DATE AS dt_plaquinha
    FROM
    	datalake_raw.gsheets_branding_where_is_plaquinha p
    JOIN fact_house_listings fhl
    	ON p.id_house = substring(fhl.sk_house_listing,1,9)
    JOIN dim_region dr
    	ON fhl.sk_region = dr.sk_region
    GROUP BY 
    	1,2,3
    UNION 
    SELECT 
        gsps.house_id::BIGINT AS id_house,
        dr.city_group,
        dpj.dt_photos_uploaded AS dt_plaquinha
    FROM 
        datalake_raw.gsheets_aux_check_photo_sender gsps
    LEFT JOIN dim_photo_job dpj 
        ON dpj.sk_photo_job = gsps.job_id_fl
    LEFT JOIN fact_house_listings fhl
    	ON gsps.house_id = substring(fhl.sk_house_listing,1,9)
    LEFT JOIN dim_region dr
    	ON fhl.sk_region = dr.sk_region
    WHERE 
        gsps.tem_plaquinha <> ''
    GROUP BY 
    	1,2,3
),
new_plaquinhas_daily AS (
    SELECT 
	city_group,
	NULL::TEXT AS mkt_origin,
	NULL::TEXT AS mkt_channel,
	NULL::TEXT AS mkt_medium,
	NULL::TEXT AS mkt_source,
	NULL::TEXT AS utm_campaign,
	NULL::TEXT AS utm_term,
	NULL::TEXT AS utm_content,
	NULL::BOOL AS is_qr_code_user,
	NULL::BOOL AS is_phone_user,
	NULL::BOOL AS is_chat_user,
	NULL::INT AS visits_booked,
	NULL::INT AS bookings_confirmed,
	NULL::INT AS offers_submitted,
	NULL::INT AS offers_approved,
	NULL::INT AS documents_first_sent,
	NULL::INT AS credit_approved,
	NULL::INT AS contracts_signed,
	count(id_house) AS new_plaquinhas,
	NULL::INT AS ongoing_plaquinhas,
	dt_plaquinha AS dt_event
    FROM 
	plaquinhas
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,20,21
),
--------------------------------------------
-- Query Ongoing Listings with plaquinhas --
--------------------------------------------
daily_published_listings AS (
    SELECT
	f.sk_house_listing,
	f.status_history,
	d.date,
	d.week_start,
	d.weekday_name,
	d.month_start,
	d.month_end,
	ROW_NUMBER() OVER(PARTITION BY f.sk_house_listing, d.date ORDER BY f.ts_status_start DESC) AS order_status -- daily order status
    FROM 
	fact_house_listing_status f
    JOIN dim_date d ON 
	d.sk_date between nullif(f.sk_status_start_date,-1) AND COALESCE(to_char(to_date(nullif(sk_status_end_date, -1), 'YYYYMMDD') - 1, 'YYYYMMDD')::bigint, to_char(current_date -1, 'YYYYMMDD')::bigint)
    WHERE 
	f.status_history = 'publicado' -- consider only published status
	AND substring(sk_house_listing,10,12) <> '000' -- consider only listings that already started publication
	AND substring(sk_house_listing,1,9) IN (SELECT id_house FROM plaquinhas)
),
daily_published_listings_adjusted AS (
    SELECT
	fhs.sk_house_listing,
	fhs.date,
	fhs.week_start,
	fhs.weekday_name,
	fhs.month_start,
	fhs.month_end,
	fhs.order_status,
	fhs.status_history,
	fhl.sk_region
    FROM
	daily_published_listings fhs
	LEFT JOIN fact_house_listings fhl ON
	fhs.sk_house_listing = fhl.sk_house_listing
	LEFT JOIN dim_region dr ON
	fhl.sk_region = dr.sk_region
    WHERE
	fhs.order_status = 1
	AND dr.city_group IS NOT NULL
),
ongoing_plaquinhas_daily AS(
	SELECT 
	    city_group,
	    NULL::TEXT AS mkt_origin,
	    NULL::TEXT AS mkt_channel,
	    NULL::TEXT AS mkt_medium,
	    NULL::TEXT AS mkt_source,
	    NULL::TEXT AS utm_campaign,
	    NULL::TEXT AS utm_term,
	    NULL::TEXT AS utm_content,
	    NULL::BOOL AS is_qr_code_user,
	    NULL::BOOL AS is_phone_user,
	    NULL::BOOL AS is_chat_user,
	    NULL::INT AS visits_booked,
	    NULL::INT AS bookings_confirmed,
	    NULL::INT AS offers_submitted,
	    NULL::INT AS offers_approved,
	    NULL::INT AS documents_first_sent,
	    NULL::INT AS credit_approved,
	    NULL::INT AS contracts_signed,
	    NULL::INT AS new_plaquinhas,
	    count(distinct sk_house_listing) AS ongoing_plaquinhas,
		date AS dt_event
	FROM 
	    daily_published_listings_adjusted dpla
	JOIN dim_region dr
		ON dpla.sk_region = dr.sk_region
	WHERE 
	     date >= DATE('2021-02-19')
	GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,21
)	
SELECT
    city_group,
    mkt_origin,
    mkt_channel,
    mkt_medium,
    mkt_source,
    utm_campaign,
    utm_term,
    utm_content,
    is_qr_code_user,
    is_phone_user,
    is_chat_user,
    SUM(visits_booked) AS visits_booked,
    SUM(bookings_confirmed) AS bookings_confirmed,
    SUM(offers_submitted) AS offers_submitted,
    SUM(offers_approved) AS offers_approved,
    SUM(documents_first_sent) AS documents_first_sent,
    SUM(credit_approved) AS credit_approved,
    SUM(contracts_signed) AS contracts_signed,
    NULL::INT AS new_plaquinhas,
    NULL::INT AS ongoing_plaquinhas,
    date_trunc('day',date_event) AS dt_event
FROM 
    funnel_counts fc
JOIN user_by_channel 
	ON user_by_channel.sk_user = fc.sk_client 
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,21
UNION ALL 
SELECT 
    *
FROM
    new_plaquinhas_daily
UNION ALL
SELECT 
    *
FROM
    ongoing_plaquinhas_daily
