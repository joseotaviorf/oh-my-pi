WITH buyer_review AS (
    WITH buyer_review_ranked AS (
        SELECT
            id_reviewed,
            id_reviewer,
            dt_creation,
            ROW_NUMBER() OVER (PARTITION BY id_reviewed, id_reviewer ORDER BY dt_creation ASC) AS rn
        FROM
            datalake_insider_clean.review
        WHERE
            type = 'tenant_visit'
    )
    SELECT
        id_reviewed,
        id_reviewer,
        dt_creation
    FROM
        buyer_review_ranked
    WHERE
        rn = 1
),
status_log AS (
  WITH status_log_ranked AS (
    SELECT
      id_schedule,
      id_author_user,
      ROW_NUMBER() OVER (PARTITION BY id_schedule ORDER BY ts_created) AS rn
    FROM
      datalake_ebdb_clean.visit_status_log
    WHERE
      event_type IN ('VISIT_REQUESTED', 'VISIT_RESCHEDULED')
      AND ts_created >= '2024-08-01'
  )
  SELECT
    id_schedule,
    id_author_user
  FROM
    status_log_ranked
  WHERE
    rn = 1
)
SELECT DISTINCT
    b.id AS id_booking,
    b.id_sale_flow,
    b.id_house,
    h.id_region,
    svh.id_business_unit,
    COALESCE(b.sk_broker_supply, -1) AS sk_broker_supply,
    COALESCE(b.sk_broker_demand, -1) AS sk_broker_demand,
    b.partner_3p_supply,
    b.partner_3p_demand,
    b.is_3p_supply,
    b.is_3p_demand,
    b.is_3p_lead_gen,
    b.has_3p_access_control,
    b.id_agent,
    ua.id AS id_user_agent,
    svh.id_user_en AS id_user_en,
    b.id_sale_fixed_agent AS id_fixed_agent,
    b.id_visitor AS id_buyer,
    h.id_user AS id_seller,
    COALESCE(vsl.id_author_user,b.id_attendant, b.id_user_creation) AS id_user_creation,
    b.id_user_cancelation AS id_user_cancelation,
    b.id_user_sale_attendence_5a,
    b.id_user_secretariat_on_visit_date,
    b.id_user_last_secretariat,
    b.id_visit,
    b.code AS visit_code,
    b.id AS id_buyer_booking_review,
    b.hub_agent_region AS hub_agent_region,
    COALESCE(b.is_hub_flow,FALSE) AS is_hub_flow,
    COALESCE(b.is_house_rented,FALSE) AS is_house_rented,
    lst.sale_type,
    b.days_visit_cancelled_to_visit,
    b.days_visit_booked_to_visit,
    b.days_visit_booked_to_visit_cancelled,
    b.days_visit_booked_to_visit_completed,
    b.ts_created AS ts_booking_created,
    b.ts_booking_utc AS ts_visit,
    b.ts_first_canceled AS ts_visit_canceled,
    IF(b.is_visit_completed, b.ts_booking_utc, NULL) AS ts_visit_completed,
    b.ts_visit_fup AS ts_visit_follow_up,
    br.dt_creation AS ts_buyer_review_rating,
    NOW() AS ts_load
FROM
    datalake_booking.booking AS b
JOIN
    datalake_ebdb_clean.house AS h
        ON h.id = b.id_house
LEFT JOIN
    datalake_sale_primary_market.listing_sale_type AS lst
        ON lst.id_house = b.id_house
LEFT JOIN
    datalake_sale_visit_hubs.sale_visit_hubs AS svh
        ON svh.id_booking = b.id
LEFT JOIN
    buyer_review AS br
        ON b.code = br.id_reviewed
        AND b.id_visitor = br.id_reviewer
LEFT JOIN
    datalake_ebdb_clean.user AS ua
        ON ua.id_agent = b.id_agent
LEFT JOIN
    status_log AS vsl
        ON b.id = vsl.id_schedule
WHERE
    b.visit_intent = 'SALE'
