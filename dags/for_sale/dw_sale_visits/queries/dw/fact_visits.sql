SELECT
    COALESCE(id_booking, -1) AS sk_booking,
    COALESCE(id_sale_flow, -1) AS sk_sale_flow,
    COALESCE(id_house, -1) AS sk_house,
    COALESCE(id_region, -1) AS sk_region,
    COALESCE(id_business_unit, -1) AS sk_business_unit,
    COALESCE(sk_company_supply, -1) AS sk_company_supply,
    COALESCE(sk_company_demand, -1) AS sk_company_demand,
    COALESCE(id_agent, -1) AS sk_agent,
    COALESCE(id_user_agent, -1) AS sk_user_agent,
    COALESCE(id_user_en, -1) AS sk_user_en,
    COALESCE(id_fixed_agent, -1) AS sk_fixed_agent,
    COALESCE(id_buyer, -1) AS sk_buyer,
    COALESCE(id_seller, -1) AS sk_seller,
    COALESCE(id_user_creation, -1) AS sk_user_creation,
    COALESCE(id_user_cancelation, -1) AS sk_user_cancelation,
    COALESCE(sa_creator.sk_secretariat_user_version, -1) AS sk_secretariat_booking_creator,
    COALESCE(sa_visit_date.sk_secretariat_user_version, -1) AS sk_secretariat_on_visit,
    COALESCE(sa_last_secretariat.sk_secretariat_user_version, -1) AS sk_last_secretariat,
    COALESCE(id_visit, -1) AS sk_visit,
    visit_code AS sk_visit_code,
    COALESCE(id_offer, -1) AS sk_offer,
    COALESCE(id_buyer_booking_review, -1) AS sk_buyer_booking_review,
    COALESCE(BIGINT(DATE_FORMAT(ts_booking_created, 'yyyyMMdd')), -1) AS sk_booking_created_date,
    COALESCE(BIGINT(DATE_FORMAT(ts_visit, 'yyyyMMdd')), -1) AS sk_visit_date,
    COALESCE(BIGINT(DATE_FORMAT(ts_visit_canceled, 'yyyyMMdd')), -1) AS sk_visit_canceled_date,
    COALESCE(BIGINT(DATE_FORMAT(ts_visit_completed, 'yyyyMMdd')), -1) AS sk_visit_completed_date,
    COALESCE(BIGINT(DATE_FORMAT(ts_visit_follow_up, 'yyyyMMdd')), -1) AS sk_visit_follow_up_date,
    COALESCE(BIGINT(DATE_FORMAT(ts_buyer_review_rating, 'yyyyMMdd')), -1) AS sk_buyer_review_rating_date,
    COALESCE(BIGINT(DATE_FORMAT(ts_visit_checkin, 'yyyyMMdd')), -1) AS sk_visit_checkin_date,
    hub_agent_region,
    is_hub_flow,
    is_house_rented,
    is_virtual_visit,
    days_visit_cancelled_to_visit,
    days_visit_booked_to_visit,
    days_visit_booked_to_visit_cancelled,
    days_visit_booked_to_visit_completed,
    hours_booking_to_offer,
    hours_visit_to_offer,
    ts_booking_created,
    ts_visit,
    ts_visit_canceled,
    ts_visit_completed,
    ts_visit_follow_up,
    ts_visit_checkin,
    ts_buyer_review_rating,
    NOW() AS ts_load
FROM
    datalake_sale_visit.sale_visit AS sv
LEFT JOIN
    datalake_hub_services.daily_secretariat_allocation AS sa_creator
        ON sa_creator.id_secretariat_user = sv.id_user_sale_attendence_5a
        AND sa_creator.dt_snapshot = DATE(sv.ts_booking_created)
LEFT JOIN
    datalake_hub_services.daily_secretariat_allocation AS sa_visit_date
        ON sa_visit_date.id_secretariat_user = sv.id_user_secretariat_on_visit_date
        AND sa_visit_date.dt_snapshot = LEAST(DATE(sv.ts_visit), CURRENT_DATE - INTERVAL '1' DAY)
LEFT JOIN
    datalake_hub_services.daily_secretariat_allocation AS sa_last_secretariat
        ON sa_last_secretariat.id_secretariat_user = sv.id_user_last_secretariat
        AND sa_last_secretariat.dt_snapshot = (CURRENT_DATE - INTERVAL '1' DAY)
