----------------
-- Sale Flow
WITH sale_flows AS (
    SELECT
        id_sale_flow,
        id_buyer AS id_user,
        id_house,
        ts_first_booking_created,
        ts_first_visit_completed,
        ts_first_offer_submitted,
        dt_first_offer_accepted,
        dt_sale_agreement_signed
    FROM
        datalake_sale_flows.sale_flow
    WHERE
        id_buyer IS NOT NULL
        AND id_house IS NOT NULL
        -- This clause is more correct than filtering by ts_first_event
        AND (
            ts_first_booking_created BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
            OR ts_first_visit_completed BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
            OR ts_first_offer_submitted BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
            OR dt_first_offer_accepted BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
            OR dt_sale_agreement_signed BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
        )
),
first_visit_attribution AS (
    SELECT
        sale_flows.id_user,
        sale_flows.id_house,
        ROW_NUMBER() OVER (
            PARTITION BY
                sale_flows.id_user,
                sale_flows.id_house
            ORDER BY
                booking.ts_created ASC,
                booking.id_visit ASC
        ) AS rn_sale_flow_visit,
        booking.id_visit,
        booking.id_agent,
        booking.first_update_source
    FROM
        datalake_booking.booking AS booking
    INNER JOIN
        sale_flows
            ON booking.id_sale_flow = sale_flows.id_sale_flow
    WHERE
        booking.visit_intent = 'SALE'
        AND booking.type = 'Visita'
        AND booking.id_sale_flow IS NOT NULL
),
sale_flow_metrics AS (
    SELECT
        id_user,
        id_house,
        MIN(ts_first_booking_created) AS ts_visit_booked,
        MIN(ts_first_visit_completed) AS ts_visit_completed,
        MIN(ts_first_offer_submitted) AS ts_offer,
        MIN(dt_first_offer_accepted) AS ts_offer_approved,
        MIN(dt_sale_agreement_signed) AS ts_contract_signed,
        GREATEST(
            MIN(ts_first_booking_created),
            MIN(ts_first_visit_completed),
            MIN(ts_first_offer_submitted),
            MIN(dt_first_offer_accepted),
            MIN(dt_sale_agreement_signed)
        ) AS ts_sale_flow_latest_event
    FROM
        sale_flows
    GROUP BY
        id_user,
        id_house
)
SELECT
    sale_flow_metrics.id_user,
    sale_flow_metrics.id_house,
    first_visit_attribution.id_visit AS id_visit,
    sale_flow_metrics.ts_visit_booked,
    sale_flow_metrics.ts_visit_completed,
    sale_flow_metrics.ts_offer,
    sale_flow_metrics.ts_offer_approved,
    sale_flow_metrics.ts_contract_signed,
    sale_flow_metrics.ts_sale_flow_latest_event,
    CASE
        WHEN first_visit_attribution.first_update_source = 'AGENT_PWA' THEN first_visit_attribution.id_agent
        ELSE NULL
    END AS id_agent,
    first_visit_attribution.first_update_source AS visit_creation_origin
FROM
    sale_flow_metrics
LEFT JOIN
    first_visit_attribution
        ON sale_flow_metrics.id_user = first_visit_attribution.id_user
        AND sale_flow_metrics.id_house = first_visit_attribution.id_house
        AND first_visit_attribution.rn_sale_flow_visit = 1
