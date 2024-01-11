WITH
events_agent AS (
    SELECT
        CAST(tta.tenant_id AS INT) AS sk_client,
        fhl.sk_region,
        CAST(DATE_FORMAT(CAST(first_message_ts AS TIMESTAMP), 'yyyyMMdd') AS INT) AS sk_talk_to_agent_date
    FROM datalake_talk_to_agent.talk_to_agent AS tta
        JOIN dw_rent.fact_house_listings AS fhl
          ON tta.sk_house_listing = fhl.sk_house_listing
    WHERE
        tta.business_context = 'RENT'
        AND tta.first_message_ts IS NOT NULL
),
events_user AS (
    SELECT DISTINCT
        COALESCE(rf.sk_client, ta.sk_client) AS sk_client,
        dr.city_group,
        sk_booking_created_date,
        sk_visit_date,
        flg_visit_completed,
        sk_reservation_created_date,
        sk_offer_submitted_date,
        sk_offer_approved_date,
        sk_tenant_first_doc_sent_date,
        sk_tenant_doc_complete_date AS sk_tenant_doc_complete_date_old,
        COALESCE(COALESCE(NULLIF(sk_tenant_doc_complete_date,-1),NULLIF(sk_credit_analysis_init_date,-1)),-1) AS sk_tenant_doc_complete_date,
        sk_credit_analysis_init_date,
        sk_credit_analysis_approved_date,
        sk_credit_analysis_end_date,
        sk_contract_created_date,
        sk_contract_signed_date,
        sk_talk_to_agent_date,
        sk_booking,
        sk_offer,
        sk_reservation,
        sk_contract,
        sk_visit
    FROM dw_rent.fact_listing_rent_flows rf
    FULL OUTER JOIN events_agent AS ta
    ON rf.sk_client = ta.sk_client AND rf.sk_region = ta.sk_region
    LEFT JOIN dw_public.dim_region dr
    ON COALESCE(rf.sk_region, ta.sk_region) = dr.sk_region
),
aux_grouped_events_user AS (
    SELECT
        sk_client,
        city_group,
        sk_booking_created_date,
        sk_visit_date,
        flg_visit_completed,
        sk_reservation_created_date,
        sk_offer_submitted_date,
        sk_offer_approved_date,
        sk_tenant_first_doc_sent_date,
        sk_tenant_doc_complete_date_old,
        sk_tenant_doc_complete_date,
        sk_credit_analysis_init_date,
        sk_credit_analysis_approved_date,
        sk_credit_analysis_end_date,
        sk_contract_created_date,
        sk_contract_signed_date,
        sk_talk_to_agent_date,
        COUNT(DISTINCT CASE WHEN sk_booking_created_date > 0 THEN sk_booking END) AS bookings_created,
        COUNT(DISTINCT CASE WHEN sk_visit_date > 0 AND flg_visit_completed = true THEN sk_visit END) AS visits_completed,
        COUNT(DISTINCT CASE WHEN sk_offer_submitted_date > 0 THEN sk_offer END) AS offers_submitted,
        COUNT(DISTINCT CASE WHEN sk_offer_approved_date > 0 THEN sk_offer END) AS offers_approved,
        COUNT(DISTINCT CASE WHEN sk_reservation_created_date > 0 THEN sk_reservation END) AS reservations_created,
        COUNT(DISTINCT CASE WHEN sk_contract_signed_date > 0 THEN sk_contract END) AS contracts_signed
    FROM
        events_user
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17
),
grouped_events_user AS (
    SELECT
        sk_client AS sk_client_grouped,
        SUM(bookings_created) AS bookings_created,
        SUM(visits_completed) AS visits_completed,
        SUM(offers_submitted) AS offers_submitted,
        SUM(offers_approved) AS offers_approved,
        SUM(reservations_created) AS reservations_created,
        SUM(contracts_signed) AS contracts_signed
    FROM
        aux_grouped_events_user
    GROUP BY 1
),
ordered_events_user AS (
    SELECT
        eu.*,
        ROW_NUMBER() OVER(PARTITION BY sk_client ORDER BY NULLIF(sk_booking_created_date,-1) NULLS LAST) AS order_booking_created,
        ROW_NUMBER() OVER(PARTITION BY sk_client ORDER BY NULLIF(sk_visit_date,-1) ASC NULLS LAST, flg_visit_completed DESC NULLS FIRST) AS order_visit,
        ROW_NUMBER() OVER(PARTITION BY sk_client ORDER BY NULLIF(sk_reservation_created_date,-1) NULLS LAST) AS order_reservation,
        ROW_NUMBER() OVER(PARTITION BY sk_client ORDER BY NULLIF(sk_offer_submitted_date,-1) NULLS LAST) AS order_offer_submitted,
        ROW_NUMBER() OVER(PARTITION BY sk_client ORDER BY NULLIF(sk_offer_approved_date,-1) NULLS LAST) AS order_offer_approved,
        ROW_NUMBER() OVER(PARTITION BY sk_client ORDER BY NULLIF(sk_tenant_first_doc_sent_date,-1) NULLS LAST) AS order_tenant_first_doc_sent,
        ROW_NUMBER() OVER(PARTITION BY sk_client ORDER BY NULLIF(COALESCE(sk_tenant_doc_complete_date,sk_credit_analysis_init_date),-1) NULLS LAST) AS order_tenant_doc_complete,
        ROW_NUMBER() OVER(PARTITION BY sk_client ORDER BY NULLIF(sk_credit_analysis_init_date,-1) NULLS LAST) AS order_credit_analysis_init,
        ROW_NUMBER() OVER(PARTITION BY sk_client ORDER BY NULLIF(sk_credit_analysis_approved_date,-1) NULLS LAST) AS order_credit_analysis_approved,
        ROW_NUMBER() OVER(PARTITION BY sk_client ORDER BY NULLIF(sk_credit_analysis_end_date,-1) NULLS LAST) AS order_credit_analysis_end,
        ROW_NUMBER() OVER(PARTITION BY sk_client ORDER BY NULLIF(sk_contract_created_date,-1) NULLS LAST) AS order_contract_created,
        ROW_NUMBER() OVER(PARTITION BY sk_client ORDER BY NULLIF(sk_contract_signed_date,-1) NULLS LAST) AS order_contract_signed,
        ROW_NUMBER() OVER(PARTITION BY sk_client ORDER BY NULLIF(sk_talk_to_agent_date,-1) NULLS LAST) AS order_talk_to_agent,
        bookings_created,
        visits_completed,
        offers_submitted,
        offers_approved,
        reservations_created,
        contracts_signed
    FROM
        events_user AS eu
    LEFT JOIN
        grouped_events_user AS ge
    ON
        eu.sk_client = ge.sk_client_grouped
),
events_user_metrics AS (
    SELECT DISTINCT
        sk_client,
        city_group,
        sk_booking_created_date,
        sk_visit_date,
        flg_visit_completed,
        sk_reservation_created_date,
        sk_offer_submitted_date,
        sk_offer_approved_date,
        sk_tenant_first_doc_sent_date,
        sk_tenant_doc_complete_date AS sk_tenant_doc_complete_date_old,
        sk_tenant_doc_complete_date,
        sk_credit_analysis_init_date,
        sk_credit_analysis_approved_date,
        sk_credit_analysis_end_date,
        sk_contract_created_date,
        sk_contract_signed_date,
        sk_talk_to_agent_date,
    -- order of events
        order_booking_created,
        order_visit,
        order_reservation,
        order_offer_submitted,
        order_offer_approved,
        order_tenant_first_doc_sent,
        order_tenant_doc_complete,
        order_credit_analysis_init,
        order_credit_analysis_approved,
        order_credit_analysis_end,
        order_contract_created,
        order_contract_signed,
        order_talk_to_agent,
    -- count of events
        bookings_created,
        visits_completed,
        offers_submitted,
        offers_approved,
        reservations_created,
        contracts_signed
    FROM
        ordered_events_user
),
first_date_user AS (
    SELECT
        sk_client,
        bookings_created,
        visits_completed,
        offers_submitted,
        offers_approved,
        reservations_created,
        contracts_signed,
        MIN(CASE WHEN order_booking_created = 1 THEN city_group END) AS first_city_group_booking,
        MIN(CASE WHEN order_offer_submitted = 1 THEN city_group END) AS first_city_group_offer,
        MIN(CASE WHEN order_talk_to_agent = 1 THEN city_group END) AS first_city_group_talk_to_agent,
        MIN(CASE WHEN order_booking_created = 1 THEN sk_booking_created_date END) AS first_booking_created_date,
        MIN(CASE WHEN order_visit = 1 AND flg_visit_completed = true then sk_visit_date END) AS first_visit_date,
        MIN(CASE WHEN order_reservation = 1 THEN sk_reservation_created_date END) AS first_reservation_date,
        MIN(CASE WHEN order_offer_submitted = 1 THEN sk_offer_submitted_date END) AS first_offer_submitted_date,
        MIN(CASE WHEN order_offer_approved = 1 THEN sk_offer_approved_date END) AS first_offer_approved_date,
        MIN(CASE WHEN order_tenant_first_doc_sent = 1 THEN sk_tenant_first_doc_sent_date END) AS first_tenant_doc_sent_date,
        MIN(CASE WHEN order_tenant_doc_complete = 1 THEN sk_tenant_doc_complete_date END) AS first_tenant_doc_complete_date,
        MIN(CASE WHEN order_credit_analysis_init = 1 THEN sk_credit_analysis_init_date END) AS first_credit_analysis_init_date,
        MIN(CASE WHEN order_credit_analysis_approved = 1 THEN sk_credit_analysis_approved_date END) AS first_credit_analysis_approved_date,
        MIN(CASE WHEN order_credit_analysis_end = 1 THEN sk_credit_analysis_END_date END) AS first_credit_analysis_END_date,
        MIN(CASE WHEN order_contract_created = 1 THEN sk_contract_created_date END) AS first_contract_created_date,
        MIN(CASE WHEN order_contract_signed = 1 THEN sk_contract_signed_date END) AS first_contract_signed_date,
        MIN(CASE WHEN order_talk_to_agent = 1 THEN sk_talk_to_agent_date END) AS first_talk_to_agent_date
    FROM
        events_user_metrics
    GROUP BY 1, 2, 3, 4, 5, 6, 7
),
users_funnel AS (
    SELECT
        sk_client as id_user,
        bookings_created,
        visits_completed,
        offers_submitted,
        offers_approved,
        reservations_created,
        contracts_signed,
        COALESCE(COALESCE(NULLIF(first_city_group_booking,-1),nullif(first_city_group_offer,-1), nullif(first_city_group_talk_to_agent,-1)),'-1') as first_city_group,
        CASE
            WHEN NULLIF(first_booking_created_date,-1) IS NULL AND NULLIF(first_talk_to_agent_date,-1) IS NULL AND NULLIF(first_offer_submitted_date,-1) IS NOT NULL then 'Offer'
            WHEN NULLIF(first_booking_created_date,-1) IS NOT NULL AND NULLIF(first_talk_to_agent_date,-1) IS NULL AND NULLIF(first_offer_submitted_date,-1) IS NULL THEN 'Booking'
            WHEN NULLIF(first_booking_created_date,-1) IS NULL AND NULLIF(first_talk_to_agent_date,-1) IS NOT NULL AND NULLIF(first_offer_submitted_date,-1) IS NULL THEN 'Talk to Agent'
            WHEN TO_DATE(first_booking_created_date::STRING,"yyyyMMdd") = LEAST(TO_DATE(first_booking_created_date::STRING,"yyyyMMdd"), TO_DATE(first_offer_submitted_date::STRING,"yyyyMMdd"), TO_DATE(first_talk_to_agent_date::STRING,"yyyyMMdd")) THEN 'Booking'
            WHEN TO_DATE(first_offer_submitted_date::STRING,"yyyyMMdd") = LEAST(TO_DATE(first_booking_created_date::STRING,"yyyyMMdd"), TO_DATE(first_offer_submitted_date::STRING,"yyyyMMdd"), TO_DATE(first_talk_to_agent_date::STRING,"yyyyMMdd")) THEN 'Offer'
            WHEN TO_DATE(first_talk_to_agent_date::STRING,"yyyyMMdd") = LEAST(TO_DATE(first_booking_created_date::STRING,"yyyyMMdd"), TO_DATE(first_offer_submitted_date::STRING,"yyyyMMdd"), TO_DATE(first_talk_to_agent_date::STRING,"yyyyMMdd")) THEN 'Talk to Agent'
        END AS first_interaction,
        TO_DATE(nullif(first_booking_created_date,'-1')::STRING,"yyyyMMdd") AS first_booking_created_date,
        TO_DATE(nullif(first_visit_date,'-1')::STRING,"yyyyMMdd") AS first_visit_date,
        TO_DATE(nullif(first_reservation_date,'-1')::STRING,"yyyyMMdd") AS first_reservation_date,
        TO_DATE(nullif(first_offer_submitted_date,'-1')::STRING,"yyyyMMdd") AS first_offer_submitted_date,
        TO_DATE(nullif(first_offer_approved_date,'-1')::STRING,"yyyyMMdd") AS first_offer_approved_date,
        TO_DATE(nullif(first_tenant_doc_sent_date,'-1')::STRING,"yyyyMMdd") AS first_tenant_doc_sent_date,
        TO_DATE(nullif(first_tenant_doc_complete_date,'-1')::STRING,"yyyyMMdd") AS first_tenant_doc_complete_date,
        TO_DATE(nullif(first_credit_analysis_init_date,'-1')::STRING,"yyyyMMdd") AS first_credit_analysis_init_date,
        TO_DATE(nullif(first_credit_analysis_approved_date,'-1')::STRING,"yyyyMMdd") AS first_credit_analysis_approved_date,
        TO_DATE(nullif(first_credit_analysis_end_date,'-1')::STRING,"yyyyMMdd") AS first_credit_analysis_end_date,
        TO_DATE(nullif(first_contract_created_date,'-1')::STRING,"yyyyMMdd") AS first_contract_created_date,
        TO_DATE(nullif(first_contract_signed_date,'-1')::STRING,"yyyyMMdd") AS first_contract_signed_date,
        TO_DATE(nullif(first_talk_to_agent_date,'-1')::STRING,"yyyyMMdd") AS first_talk_to_agent_date
    FROM
        first_date_user
)
SELECT
    id_user,
    bookings_created,
    visits_completed,
    offers_submitted,
    offers_approved,
    reservations_created,
    contracts_signed,
    first_city_group,
    first_interaction,
    first_booking_created_date,
    first_visit_date,
    first_reservation_date,
    first_offer_submitted_date,
    first_offer_approved_date,
    first_tenant_doc_sent_date,
    first_tenant_doc_complete_date,
    first_credit_analysis_init_date,
    first_credit_analysis_approved_date,
    first_credit_analysis_end_date,
    first_contract_created_date,
    first_contract_signed_date,
    first_talk_to_agent_date,
    -- diff days
    DATEDIFF(first_visit_date,first_booking_created_date) AS days_VB_VC,
    DATEDIFF(first_offer_submitted_date,first_visit_date) AS days_VC_OS,
    DATEDIFF(first_offer_approved_date,first_offer_submitted_date) AS days_OS_OA,
    DATEDIFF(first_tenant_doc_sent_date,first_offer_approved_date) AS days_OA_DS,
    DATEDIFF(first_credit_analysis_approved_date,first_tenant_doc_sent_date) AS days_DS_CA,
    DATEDIFF(first_contract_created_date,first_credit_analysis_approved_date) AS days_CA_CC,
    DATEDIFF(first_contract_signed_date,first_contract_created_date) AS days_CC_CS,
    -- diff week (diff related do week start for each event)
    (DATEDIFF(DATE_TRUNC("WEEK",first_visit_date),DATE_TRUNC("WEEK",first_booking_created_date)) / 7 )::INTEGER AS week_VB_VC,
    (DATEDIFF(DATE_TRUNC("WEEK",first_offer_submitted_date),DATE_TRUNC("WEEK",first_visit_date)) / 7 )::INTEGER AS week_VC_OS,
    (DATEDIFF(DATE_TRUNC("WEEK",first_offer_approved_date),DATE_TRUNC("WEEK",first_offer_submitted_date)) / 7 )::INTEGER AS week_OS_OA,
    (DATEDIFF(DATE_TRUNC("WEEK",first_tenant_doc_sent_date),DATE_TRUNC("WEEK",first_offer_approved_date)) / 7 )::INTEGER AS week_OA_DS,
    (DATEDIFF(DATE_TRUNC("WEEK",first_credit_analysis_approved_date),DATE_TRUNC("WEEK",first_tenant_doc_sent_date)) / 7 )::INTEGER AS week_DS_CA,
    (DATEDIFF(DATE_TRUNC("WEEK",first_contract_signed_date),DATE_TRUNC("WEEK",first_credit_analysis_approved_date)) / 7 )::INTEGER AS week_CA_CS
FROM users_funnel
