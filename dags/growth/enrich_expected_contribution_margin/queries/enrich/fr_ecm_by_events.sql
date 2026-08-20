WITH eltv_requests AS (
    SELECT
        ecm.id_request,
        ecm.id_house,
        ecm.id_user,
        ecm.id_entity,
        GET_JSON_OBJECT(ecm.request, '$.event_type') AS event_type,
        ecm.estimated_duration,
        ecm.estimated_conversion_probability,
        ecm.estimated_gross_revenue,
        ecm.estimated_net_revenue,
        ecm.estimated_contribution_margin,
        ecm.ts_event,
        ecm.ts_log
    FROM
        datalake_expected_contribution_margin.expected_contribution_margin AS ecm
    WHERE
        ecm.id_service = 'eltv'
        AND ecm.year = YEAR(DATE('{load_start_date}'))
        AND ecm.month = MONTH(DATE('{load_start_date}'))
        AND ecm.day = DAY(DATE('{load_start_date}'))
),
ecm_entities AS (
    SELECT
        COALESCE(bk.id_rent_flow, off.id_rent_flow) AS id_flow,
        ecm.id_house,
        ecm.id_user AS id_prospect,
        ecm.id_request,
        COALESCE(bk.id, off.id_offer_context) AS id_event,
        ecm.id_entity,
        ecm.event_type,
        ecm.estimated_duration / 30.0 AS estimated_contract_duration,
        ecm.estimated_conversion_probability AS estimated_conversion,
        ecm.estimated_gross_revenue,
        ecm.estimated_net_revenue,
        ecm.estimated_net_revenue AS estimated_net_revenue_after_losses,
        ecm.estimated_contribution_margin,
        DATE(ecm.ts_log) AS dt_event_time,
        COALESCE(ecm.ts_event, bk.ts_created, off.ts_created, ecm.ts_log) AS ts_event,
        ROW_NUMBER() OVER (
            PARTITION BY ecm.id_request
            ORDER BY COALESCE(bk.ts_created, off.ts_created)
        ) AS rn
    FROM
        eltv_requests AS ecm
    LEFT JOIN
        datalake_booking.booking AS bk
            ON ecm.event_type = 'VB'
            AND ecm.id_entity = bk.code
            AND bk.is_sale_visit = FALSE
    LEFT JOIN
        datalake_offer.offer AS off
            ON ecm.event_type = 'OS'
            AND ecm.id_entity = off.id_firestore
)
SELECT
    id_flow,
    id_house,
    id_prospect,
    id_request,
    id_event,
    id_entity,
    event_type,
    estimated_contract_duration,
    estimated_conversion,
    estimated_gross_revenue,
    estimated_net_revenue,
    estimated_net_revenue_after_losses,
    estimated_contribution_margin,
    dt_event_time,
    ts_event
FROM
    ecm_entities
WHERE
    rn = 1
