----------------
-- Rent Flow
WITH rent_flows AS (
    SELECT
        id_rent_flow,
        id_tenant_prospect AS id_user,
        id_house,
        ts_booking_created,
        ts_visit_completed,
        ts_direct_offer_submitted,
        ts_offer_submitted,
        ts_offer_approved,
        ts_contract_signed
    FROM
        datalake_rent_flows.rent_flows
    WHERE
        id_tenant_prospect IS NOT NULL
        AND id_house IS NOT NULL
        -- This clause is more correct than filtering by ts_rent_flow_event
        AND (
            ts_booking_created BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
            OR ts_visit_completed BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
            OR ts_direct_offer_submitted BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
            OR ts_offer_submitted BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
            OR ts_offer_approved BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
            OR ts_contract_signed BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
        )
),
first_visit_attribution AS (
    SELECT
        rent_flows.id_user,
        rent_flows.id_house,
        ROW_NUMBER() OVER (
            PARTITION BY
                rent_flows.id_user,
                rent_flows.id_house
            ORDER BY
                booking.ts_created ASC,
                booking.id_visit ASC
        ) AS rn_rent_flow_visit,
        booking.id_visit,
        booking.id_agent,
        booking.first_update_source
    FROM
        datalake_booking.booking AS booking
    INNER JOIN
        rent_flows
            ON booking.id_rent_flow = rent_flows.id_rent_flow
    WHERE
        booking.visit_intent = 'RENT'
        AND booking.type = 'Visita'
        AND booking.id_rent_flow IS NOT NULL
),
rent_flow_metrics AS (
    SELECT
        id_user,
        id_house,
        MIN(ts_booking_created) AS ts_visit_booked,
        MIN(ts_visit_completed) AS ts_visit_completed,
        MIN(ts_direct_offer_submitted) AS ts_direct_offer,
        MIN(ts_offer_submitted) AS ts_offer_submitted,
        MIN(ts_offer_approved) AS ts_offer_approved,
        MIN(COALESCE(ts_direct_offer_submitted, ts_offer_submitted)) AS ts_offer,
        MIN(ts_contract_signed) AS ts_contract_signed,
        GREATEST(
            MIN(ts_booking_created),
            MIN(ts_visit_completed),
            MIN(ts_direct_offer_submitted),
            MIN(ts_offer_submitted),
            MIN(ts_offer_approved),
            MIN(ts_contract_signed)
        ) AS ts_rent_flow_latest_event
    FROM
        rent_flows
    GROUP BY
        id_user,
        id_house
)
SELECT
    rent_flow_metrics.id_user,
    rent_flow_metrics.id_house,
    first_visit_attribution.id_visit AS id_visit,
    rent_flow_metrics.ts_visit_booked,
    rent_flow_metrics.ts_visit_completed,
    rent_flow_metrics.ts_direct_offer,
    rent_flow_metrics.ts_offer_submitted,
    rent_flow_metrics.ts_offer_approved,
    rent_flow_metrics.ts_offer,
    rent_flow_metrics.ts_contract_signed,
    rent_flow_metrics.ts_rent_flow_latest_event,
    CASE
        WHEN first_visit_attribution.first_update_source = 'AGENT_PWA' THEN first_visit_attribution.id_agent
        ELSE NULL
    END AS id_agent,
    first_visit_attribution.first_update_source AS visit_creation_origin
FROM
    rent_flow_metrics
LEFT JOIN
    first_visit_attribution
        ON rent_flow_metrics.id_user = first_visit_attribution.id_user
        AND rent_flow_metrics.id_house = first_visit_attribution.id_house
        AND first_visit_attribution.rn_rent_flow_visit = 1
