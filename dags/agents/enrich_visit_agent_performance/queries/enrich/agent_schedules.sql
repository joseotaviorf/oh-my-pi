WITH booking AS (
    SELECT 
        b.id,
        b.id_visit,
        b.id_visitor,
        b.id_agent,
        bc.cancelled_by = "Agent" AS is_booking_cancellation_by_agent,
        vcd.on_behalf_of = "AGENT" AS is_visit_cancellation_by_agent,
        b.first_update_source = "Corretores" AS is_visit_booking_by_agent,
        b.status NOT IN ('Done', 'Realizado', 'Cancelado', 'Canceled') AS is_booking_stalled,
        b.is_visit_completed,
        b.ts_created,
        b.ts_updated
    FROM
        datalake_booking.booking AS b
    LEFT JOIN
        datalake_ebdb_clean.visit_cancellation_details AS vcd
            ON vcd.id_visit = b.id_visit
    LEFT JOIN 
        datalake_booking.booking_cancellation AS bc
            ON bc.id_booking = b.id
    WHERE
        b.id_agent IS NOT NULL
        AND b.ts_created IS NOT NULL
        AND DATE(COALESCE(b.ts_updated, b.ts_created)) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
consecutive_confirmed_visits AS (
    SELECT
        b.id,
        b.id_visitor,
        b.id_agent,
        COUNT(*) OVER (
            PARTITION BY b.id_visitor, b.id_agent
            ORDER BY b.ts_created
            RANGE BETWEEN INTERVAL '28 days' PRECEDING AND CURRENT ROW
        ) AS total_consecutive_confirmed_visits,
        b.ts_created
    FROM
        booking AS b
    WHERE
        b.is_visit_completed IS TRUE
),
rent_flows_touchpoint AS (
    SELECT DISTINCT
        rf.id_booking,
        COALESCE(rf.first_touchpoint = "DIRECT", FALSE) AS has_direct_first_touchpoint
    FROM
        datalake_rent_flows.rent_flows AS rf
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY rf.id_booking ORDER BY rf.ts_updated DESC) = 1
)
SELECT
    XXHASH64(b.id_agent, b.id) AS id_agent_schedule,
    b.id_agent,
    b.id AS id_booking,
    b.id_visit,
    b.id_visitor AS id_lead,
    b.is_booking_cancellation_by_agent,
    b.is_visit_cancellation_by_agent,
    b.is_visit_booking_by_agent,
    b.is_booking_stalled,
    b.is_visit_completed,
    cv.total_consecutive_confirmed_visits >= 3 AS has_three_or_more_confirmed_visits_same_agent,
    COALESCE(rf.has_direct_first_touchpoint, FALSE) AS has_direct_first_touchpoint,
    b.ts_updated,
    b.ts_created,
    YEAR(b.ts_created) AS year,
    MONTH(b.ts_created) AS month,
    DAY(b.ts_created) AS day
FROM 
    booking AS b
LEFT JOIN
    consecutive_confirmed_visits AS cv
        ON cv.id = b.id
        AND cv.id_agent = b.id_agent
        AND cv.id_visitor = b.id_visitor
        AND cv.ts_created = b.ts_created
LEFT JOIN
    rent_flows_touchpoint AS rf
        ON rf.id_booking = b.id