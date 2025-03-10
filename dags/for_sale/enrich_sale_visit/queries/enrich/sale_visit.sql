WITH offer_after_booking AS (
    SELECT
        id_booking,
        id_offer,
        hours_booking_to_offer,
        hours_visit_to_offer
    FROM
        datalake_offer.sale_offer
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_booking ORDER BY ts_offer_submitted) = 1
),
buyer_review AS (
    SELECT
        id_reviewed,
        id_reviewer,
        dt_creation
    FROM
        datalake_insider_clean.review
    WHERE
        type = 'tenant_visit'
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_reviewed, id_reviewer ORDER BY dt_creation ASC) = 1
), 
status_log AS (
  SELECT 
    id_schedule,
    id_author_user 
  FROM 
    datalake_ebdb_clean.visit_status_log 
  WHERE 
    event_type IN ('VISIT_REQUESTED', 'VISIT_RESCHEDULED')
    AND ts_created >= '2024-08-01'
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_schedule ORDER BY ts_created) = 1)
SELECT
    b.id AS id_booking,
    b.id_sale_flow,
    b.id_house,
    h.id_region,
    svh.id_business_unit,
    cs_supply.sk_company AS sk_company_supply,
    COALESCE(NULLIF(cs_demand.sk_company, -1), b.id_company_demand) AS sk_company_demand,
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
    so.id_offer,
    b.id AS id_buyer_booking_review,
    b.hub_agent_region AS hub_agent_region,
    COALESCE(b.is_hub_flow,FALSE) AS is_hub_flow,
    COALESCE(b.is_house_rented,FALSE) AS is_house_rented,
    COALESCE(b.is_virtual_visit,FALSE) AS is_virtual_visit,
    b.days_visit_cancelled_to_visit,
    b.days_visit_booked_to_visit,
    b.days_visit_booked_to_visit_cancelled,
    b.days_visit_booked_to_visit_completed,
    so.hours_booking_to_offer,
    so.hours_visit_to_offer,
    b.ts_created AS ts_booking_created,
    b.ts_booking_utc AS ts_visit,
    b.ts_first_canceled AS ts_visit_canceled,
    IF(b.is_visit_completed, b.ts_booking_utc, NULL) AS ts_visit_completed,
    b.ts_visit_fup AS ts_visit_follow_up,
    b.ts_checkin AS ts_visit_checkin,
    br.dt_creation AS ts_buyer_review_rating,
    NOW() AS ts_load
FROM
    datalake_booking.booking AS b
JOIN
    datalake_ebdb_clean.house AS h
        ON h.id = b.id_house
LEFT JOIN
    offer_after_booking AS so
        ON b.id = so.id_booking
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
    datalake_rede_company.company_sks AS cs_demand
        ON (b.id_company_demand IS NOT NULL
        AND b.id_company_demand = cs_demand.id_hubspot)
        OR (b.id_company_demand IS NULL
        AND b.partner_3p_demand = cs_demand.extracted_3p_tag)
LEFT JOIN
    datalake_rede_company.company_sks AS cs_supply
        ON (
          b.uuid_company_supply IS NOT NULL
          AND b.uuid_company_supply = cs_supply.uuid_company
        ) OR (
          b.uuid_company_supply IS NULL
          AND b.id_company_supply IS NOT NULL
          AND b.id_company_supply = cs_supply.id_hubspot
        ) OR (
          b.uuid_company_supply IS NULL
          AND b.id_company_supply IS NULL
          AND b.partner_3p_supply = cs_supply.extracted_3p_tag
        )
LEFT JOIN 
  status_log AS vsl
    ON b.id = vsl.id_schedule
WHERE
    b.visit_intent = 'SALE'