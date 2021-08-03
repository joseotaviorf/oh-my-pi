WITH offer_after_booking AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY id_booking ORDER BY ts_offer_submitted) AS offer_order
  FROM
    datalake_offer.sale_offer
)
SELECT
    COALESCE(b.id, -1) AS sk_booking,
    COALESCE(b.id_sale_flow, -1) AS sk_sale_flow,
    COALESCE(b.id_house, -1) AS sk_house,
    COALESCE(h.id_region, -1) AS sk_region,
    COALESCE(b.id_agent, -1) AS sk_agent,
    COALESCE(ua.id, -1) AS sk_user_agent,
    COALESCE(b.id_sale_fixed_agent, -1) AS sk_fixed_agent,
    COALESCE(b.id_visitor, -1) AS sk_buyer,
    COALESCE(h.id_user, -1) AS sk_seller,
    COALESCE(b.id_user_creation, -1) AS sk_user_creation,
    COALESCE(b.id_user_cancelation, -1) AS sk_user_cancelation,
    COALESCE(b.id_visit, -1) AS sk_visit,
    b.code AS sk_visit_code,
    COALESCE(so.id_offer, -1) AS sk_offer,
    COALESCE(ar.id, -1) AS sk_agent_booking_review,
    COALESCE(b.id, -1) AS sk_buyer_booking_review,
    COALESCE(BIGINT(DATE_FORMAT(b.ts_created, 'yyyyMMdd')), -1) AS sk_booking_created_date,
    COALESCE(BIGINT(DATE_FORMAT(b.ts_booking_utc, 'yyyyMMdd')), -1) AS sk_visit_date,
    COALESCE(BIGINT(DATE_FORMAT(b.ts_first_canceled, 'yyyyMMdd')), -1) AS sk_visit_canceled_date,
    IF(b.is_visit_completed, BIGINT(DATE_FORMAT(b.ts_booking_utc, 'yyyyMMdd')), -1) AS sk_visit_completed_date,
    COALESCE(BIGINT(DATE_FORMAT(b.ts_visit_fup, 'yyyyMMdd')), -1) AS sk_visit_follow_up_date,
    COALESCE(BIGINT(DATE_FORMAT(ar.ts_created, 'yyyyMMdd')), -1) AS sk_agent_review_rating_date,
    COALESCE(BIGINT(DATE_FORMAT(br.dt_creation, 'yyyyMMdd')), -1) AS sk_buyer_review_rating_date,
    COALESCE(b.is_hub_flow,FALSE) AS is_hub_flow,
    COALESCE(b.is_house_rented,FALSE) AS is_house_rented,
    COALESCE(b.is_virtual_visit,FALSE) AS is_virtual_visit,
    b.days_visit_cancelled_to_visit,
    b.days_visit_booked_to_visit,
    b.days_visit_booked_to_visit_cancelled,
    b.days_visit_booked_to_visit_completed,
    so.hours_booking_to_offer,
    so.hours_visit_to_offer,
    NOW() AS ts_load
FROM
    datalake_booking.booking AS b
JOIN
    datalake_ebdb_clean.house AS h
      ON h.id = b.id_house
LEFT JOIN
    offer_after_booking AS so
      ON b.id = so.id_booking
      AND offer_order = 1
LEFT JOIN
    datalake_ebdb_clean.real_estate_agent_rating AS ar
      ON ar.id = b.id_real_estate_agent_rating
LEFT JOIN
    datalake_insider_clean.review AS br
      ON b.code = br.id_reviewed
      AND b.id_visitor = br.id_reviewer
      AND br.type='tenant_visit'
LEFT JOIN
    datalake_ebdb_clean.user ua
      ON ua.id_agent = b.id_agent
WHERE
   b.visit_intent = 'SALE'
