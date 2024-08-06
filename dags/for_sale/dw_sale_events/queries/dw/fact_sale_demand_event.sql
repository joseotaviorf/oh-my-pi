WITH bookings AS (
    SELECT
        fv.sk_booking,
        sk_booking_created_date,
        sk_visit_completed_date,
        fv.sk_visit_canceled_date,
        fv.sk_house,
        fv.sk_region,
        fv.sk_buyer,
        fv.sk_seller,
        fv.sk_agent,
        fac.sk_work_contract AS sk_agent_work_contract,
        fv.sk_business_unit,
        fv.sk_company_supply,
        fv.sk_company_demand,
        fv.sk_secretariat_booking_creator,
        fv.sk_secretariat_on_visit,
        fv.sk_last_secretariat,
        fv.ts_booking_created,
        fv.ts_visit_completed,
        fv.ts_visit_canceled
    FROM
        dw_sale.fact_visits AS fv
    JOIN
        datalake_booking.booking AS b
            ON b.id = fv.sk_booking
    LEFT JOIN
        dw_agent.fact_agent_contract AS fac
            ON fac.sk_agent = b.id_agent
            AND b.ts_created BETWEEN fac.ts_status_started AND COALESCE(fac.ts_status_ended, NOW())
),
offers AS (
    SELECT
        fo.sk_offer,
        fo.sk_offer_submitted_date,
        fo.sk_offer_accepted_date,
        fo.sk_sale_agreement_created_date,
        fo.sk_sale_agreement_signed_date,
        fo.sk_offer_dismissed_date,
        fo.sk_booking,
        fo.sk_house,
        fo.sk_region,
        fo.sk_buyer,
        fo.sk_owner AS sk_seller,
        fo.sk_agent,
        fac.sk_work_contract AS sk_agent_work_contract,
        fo.sk_business_unit,
        fo.sk_company_supply,
        fo.sk_company_demand,
        fo.sk_secretariat_booking_creator,
        fo.sk_secretariat_on_offer_submitted,
        fo.sk_secretariat_on_offer_accepted,
        fo.sk_secretariat_on_offer_dismissed,
        fo.sk_secretariat_on_sale_agreement_created,
        fo.sk_secretariat_on_sale_agreement_signed,
        fo.sk_last_secretariat,
        fo.ts_offer_submitted,
        fo.ts_offer_accepted,
        fo.ts_sale_agreement_created,
        fo.ts_sale_agreement_signed,
        fo.ts_offer_dismissed
    FROM
        dw_sale.fact_offers AS fo
    LEFT JOIN
        datalake_booking.booking b
            ON b.id = fo.sk_booking
    LEFT JOIN
        dw_agent.fact_agent_contract AS fac
            ON fac.sk_agent = b.id_agent
            AND b.ts_created BETWEEN fac.ts_status_started AND COALESCE(fac.ts_status_ended, NOW())
),
events AS (
    SELECT -- Visit Booked
        sk_booking_created_date AS sk_event_date,
        1 AS sk_event_type,
        sk_booking,
        -1 AS sk_offer,
        sk_house,
        sk_region,
        sk_buyer,
        sk_seller,
        sk_agent,
        sk_agent_work_contract,
        sk_business_unit,
        sk_company_supply,
        sk_company_demand,
        sk_secretariat_booking_creator,
        sk_secretariat_on_visit AS sk_secretariat_on_event,
        sk_last_secretariat,
        ts_booking_created AS ts_event
    FROM
        bookings
    WHERE
        sk_booking_created_date != -1
    UNION ALL
    SELECT -- Visit Completed
        sk_visit_completed_date AS sk_event_date,
        2 AS sk_event_type,
        sk_booking,
        -1 AS sk_offer,
        sk_house,
        sk_region,
        sk_buyer,
        sk_seller,
        sk_agent,
        sk_agent_work_contract,
        sk_business_unit,
        sk_company_supply,
        sk_company_demand,
        sk_secretariat_booking_creator,
        sk_secretariat_on_visit AS sk_secretariat_on_event,
        sk_last_secretariat,
        ts_visit_completed AS ts_event
    FROM
        bookings
    WHERE
        sk_visit_completed_date != -1
    UNION ALL
    SELECT -- Offer Submitted
        sk_offer_submitted_date AS sk_event_date,
        3 AS sk_event_type,
        sk_booking,
        sk_offer,
        sk_house,
        sk_region,
        sk_buyer,
        sk_seller,
        sk_agent,
        sk_agent_work_contract,
        sk_business_unit,
        sk_company_supply,
        sk_company_demand,
        sk_secretariat_booking_creator,
        sk_secretariat_on_offer_submitted AS sk_secretariat_on_event,
        sk_last_secretariat,
        ts_offer_submitted AS ts_event
    FROM
        offers
    WHERE
        sk_offer_submitted_date != -1
    UNION ALL
    SELECT -- Offer Accepted
        sk_offer_accepted_date AS sk_event_date,
        4 AS sk_event_type,
        sk_booking,
        sk_offer,
        sk_house,
        sk_region,
        sk_buyer,
        sk_seller,
        sk_agent,
        sk_agent_work_contract,
        sk_business_unit,
        sk_company_supply,
        sk_company_demand,
        sk_secretariat_booking_creator,
        sk_secretariat_on_offer_accepted AS sk_secretariat_on_event,
        sk_last_secretariat,
        ts_offer_accepted AS ts_event
    FROM
        offers
    WHERE
        sk_offer_accepted_date != -1
    UNION ALL
    SELECT -- Sale Agreement Created
        sk_sale_agreement_created_date AS sk_event_date,
        5 AS sk_event_type,
        sk_booking,
        sk_offer,
        sk_house,
        sk_region,
        sk_buyer,
        sk_seller,
        sk_agent,
        sk_agent_work_contract,
        sk_business_unit,
        sk_company_supply,
        sk_company_demand,
        sk_secretariat_booking_creator,
        sk_secretariat_on_sale_agreement_created AS sk_secretariat_on_event,
        sk_last_secretariat,
        ts_sale_agreement_created AS ts_event
    FROM
        offers
    WHERE
        sk_sale_agreement_created_date != -1
    UNION ALL
    SELECT -- Sale Agreement Signed
        sk_sale_agreement_signed_date AS sk_event_date,
        6 AS sk_event_type,
        sk_booking,
        sk_offer,
        sk_house,
        sk_region,
        sk_buyer,
        sk_seller,
        sk_agent,
        sk_agent_work_contract,
        sk_business_unit,
        sk_company_supply,
        sk_company_demand,
        sk_secretariat_booking_creator,
        sk_secretariat_on_sale_agreement_signed AS sk_secretariat_on_event,
        sk_last_secretariat,
        ts_sale_agreement_signed AS ts_event
    FROM
        offers
    WHERE
        sk_sale_agreement_signed_date != -1
    UNION ALL
    SELECT -- Visit canceled
        sk_visit_canceled_date AS sk_event_date,
        7 AS sk_event_type,
        sk_booking,
        -1 AS sk_offer,
        sk_house,
        sk_region,
        sk_buyer,
        sk_seller,
        sk_agent,
        sk_agent_work_contract,
        sk_business_unit,
        sk_company_supply,
        sk_company_demand,
        sk_secretariat_booking_creator,
        sk_secretariat_on_visit AS sk_secretariat_on_event,
        sk_last_secretariat,
        ts_visit_canceled AS ts_event
    FROM
        bookings
    WHERE
        sk_visit_canceled_date != -1
    UNION ALL
    SELECT -- Offer dismissed
        sk_offer_dismissed_date AS sk_event_date,
        8 AS sk_event_type,
        sk_booking,
        sk_offer,
        sk_house,
        sk_region,
        sk_buyer,
        sk_seller,
        sk_agent,
        sk_agent_work_contract,
        sk_business_unit,
        sk_company_supply,
        sk_company_demand,
        sk_secretariat_booking_creator,
        sk_secretariat_on_sale_agreement_signed AS sk_secretariat_on_event,
        sk_last_secretariat,
        ts_offer_dismissed AS ts_event
    FROM
        offers
    WHERE
        sk_offer_dismissed_date != -1
),
final_results AS (
SELECT
    CONCAT(sk_event_date,COALESCE(NULLIF(sk_booking,-1),sk_buyer),sk_event_type) AS sk_sale_demand_event,
    e.sk_event_date,
    e.sk_event_type,
    e.sk_booking,
    e.sk_offer,
    COALESCE(e.sk_house, -1) AS sk_house,
    COALESCE(e.sk_region, -1) AS sk_region,
    COALESCE(e.sk_buyer, -1) AS sk_buyer,
    COALESCE(e.sk_seller, -1) AS sk_seller,
    COALESCE(e.sk_agent, -1) AS sk_agent,
    COALESCE(e.sk_agent_work_contract, -1) AS sk_agent_work_contract,
    COALESCE(e.sk_business_unit, -1) AS sk_business_unit,
    COALESCE(e.sk_company_supply, -1) AS sk_company_supply,
    COALESCE(e.sk_company_demand, -1) AS sk_company_demand,
    COALESCE(e.sk_secretariat_booking_creator, -1) AS sk_secretariat_booking_creator,
    COALESCE(e.sk_secretariat_on_event, -1) AS sk_secretariat_on_event,
    COALESCE(e.sk_last_secretariat, -1) AS sk_last_secretariat,
    YEAR(e.ts_event) AS year,
    MONTH(e.ts_event) AS month,
    DAY(e.ts_event) AS day,
    e.ts_event,
    NOW() AS ts_load
FROM
    events AS e
WHERE
    sk_event_date IS NOT NULL)
SELECT
    sk_sale_demand_event,
    sk_event_date,
    sk_event_type,
    sk_booking,
    sk_offer,
    sk_house,
    sk_region,
    sk_buyer,
    sk_seller,
    sk_agent,
    sk_agent_work_contract,
    sk_business_unit,
    sk_company_supply,
    sk_company_demand,
    sk_secretariat_booking_creator,
    sk_secretariat_on_event,
    sk_last_secretariat,
    year,
    month,
    day,
    ts_event,
    ts_load
FROM
    final_results
GROUP BY ALL
