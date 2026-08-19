WITH ecm_bookings AS (
    SELECT
        CONCAT(CAST(ecm.id_user AS VARCHAR), '_', CAST(ecm.id_house AS VARCHAR)) AS id_flow,
        CAST(ecm.id_user AS INT) AS id_prospect,
        CAST(ecm.id_house AS INT) AS id_house,
        ecm.id_request,
        CAST(bk.id AS INT) AS id_event,
        ecm.id_entity AS visit_code,
        'VB' AS event_type,
        ecm.estimated_conversion_probability AS estimated_conversion,
        ecm.estimated_discount,
        ecm.estimated_gross_revenue,
        ecm.estimated_net_revenue,
        ecm.estimated_contribution_margin,
        DATE(ecm.ts_log) AS dt_event_time,
        COALESCE(bk.ts_created, ecm.ts_log) AS ts_event,
        ROW_NUMBER() OVER (
            PARTITION BY ecm.id_request
            ORDER BY bk.ts_created
        ) AS rn
    FROM
        datalake_expected_contribution_margin.expected_contribution_margin AS ecm
    LEFT JOIN
        datalake_booking.booking AS bk
            ON ecm.id_entity = bk.code
            AND bk.is_sale_visit = TRUE
    WHERE
        ecm.id_service = 'for-sale-ecm'
        AND ecm.year = YEAR(DATE('{load_start_date}'))
        AND ecm.month = MONTH(DATE('{load_start_date}'))
        AND ecm.day = DAY(DATE('{load_start_date}'))
)
SELECT
    id_flow,
    id_prospect,
    id_house,
    id_request,
    id_event,
    visit_code,
    event_type,
    estimated_conversion,
    estimated_discount,
    estimated_gross_revenue,
    estimated_net_revenue,
    estimated_contribution_margin,
    dt_event_time,
    ts_event
FROM
    ecm_bookings
WHERE
    rn = 1
