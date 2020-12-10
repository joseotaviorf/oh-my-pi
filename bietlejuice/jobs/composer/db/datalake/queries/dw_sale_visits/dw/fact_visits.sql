SELECT
    COALESCE(b.id, -1) AS sk_booking,
    COALESCE(b.id_sale_flow, -1) AS sk_sale_flow,
    COALESCE(b.id_house, -1) AS sk_house,
    COALESCE(h.id_region, -1) AS sk_region,
    COALESCE(b.id_agent, -1) AS sk_agent,
    COALESCE(b.id_visitor, -1) AS sk_buyer,
    COALESCE(h.id_user, -1) AS sk_seller,
    COALESCE(b.id_visit, -1) AS sk_visit,
    COALESCE(so.id_offer, -1) AS sk_offer,
    COALESCE(ar.id, -1) AS sk_agent_booking_review,
    COALESCE(br.id, -1) AS sk_buyer_booking_review,
    COALESCE(BIGINT(DATE_FORMAT(b.ts_created, 'yyyyMMdd')), -1) AS sk_booking_created_date,
    COALESCE(BIGINT(DATE_FORMAT(b.ts_booking_utc, 'yyyyMMdd')), -1) AS sk_visit_date,
    COALESCE(BIGINT(DATE_FORMAT(b.ts_first_canceled, 'yyyyMMdd')), -1) AS sk_visit_canceled_date,
    IF(b.is_visit_completed, BIGINT(DATE_FORMAT(b.ts_booking_utc, 'yyyyMMdd')), -1) AS sk_visit_completed_date,
    COALESCE(BIGINT(DATE_FORMAT(b.ts_visit_fup, 'yyyyMMdd')), -1) AS sk_visit_follow_up_date,
    COALESCE(BIGINT(DATE_FORMAT(ar.ts_created, 'yyyyMMdd')), -1) AS sk_agent_review_rating_date,
    COALESCE(BIGINT(DATE_FORMAT(br.dt_creation, 'yyyyMMdd')), -1) AS sk_buyer_review_rating_date,
    b.days_visit_booked_to_visit_cancelled,
    b.days_visit_booked_to_visit_completed,
    NOW() AS ts_load
FROM
    datalake_booking.booking AS b
JOIN datalake_ebdb_clean.house AS h 
    ON h.id = b.id_house
LEFT JOIN datalake_offer.sale_offer AS so
    ON b.id = so.id_booking
LEFT JOIN datalake_ebdb_clean.real_estate_agent_rating AS ar 
    ON ar.id = b.id_real_estate_agent_rating
LEFT JOIN datalake_insider_clean.review AS br 
    ON b.code = br.id_reviewed
    AND br.status = 'DONE'
WHERE
    b.visit_intent = 'SALE'
