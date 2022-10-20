WITH bookings AS (
    SELECT
        fv.sk_booking,
        sk_booking_created_date,
        sk_visit_completed_date,
        fv.sk_house,
        fv.sk_region,
        fv.sk_buyer,
        fv.sk_seller,
        fv.sk_agent,
        fac.sk_work_contract AS sk_agent_work_contract,
        fv.sk_business_unit,
        b.partner_3p_supply,
        b.partner_3p_demand
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
        fo.sk_booking,
        fo.sk_house,
        fo.sk_region,
        fo.sk_buyer,
        fo.sk_owner AS sk_seller,
        fo.sk_agent,
        fac.sk_work_contract AS sk_agent_work_contract,
        fo.sk_business_unit,
        so.partner_3p_supply,
        so.partner_3p_demand
    FROM
        dw_sale.fact_offers AS fo
    JOIN
        datalake_offer.sale_offer AS so
            ON fo.sk_offer = so.id_offer
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
        partner_3p_supply,
        partner_3p_demand
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
        partner_3p_supply,
        partner_3p_demand
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
        partner_3p_supply,
        partner_3p_demand
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
        partner_3p_supply,
        partner_3p_demand
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
        partner_3p_supply,
        partner_3p_demand
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
        partner_3p_supply,
        partner_3p_demand
    FROM
        offers
    WHERE
        sk_sale_agreement_signed_date != -1
)
SELECT
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
    COALESCE(dcs.sk_company, -1) AS sk_company_supply,
    COALESCE(dcd.sk_company, -1) AS sk_company_demand,
    dd.year,
    dd.month,
    dd.day,
    NOW() AS ts_load
FROM
    events AS e
LEFT JOIN
    dw_rede.dim_company AS dcs
        ON dcs.extracted_3p_tag = e.partner_3p_supply
LEFT JOIN
    dw_rede.dim_company AS dcd
        ON dcd.extracted_3p_tag = e.partner_3p_demand
JOIN
    dw_public.dim_date AS dd
        ON e.sk_event_date = dd.sk_date
WHERE
    dd.year = {year}
    AND dd.month = {month}
    AND dd.day = {day}