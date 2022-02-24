WITH aux_events AS (
    SELECT
        CAST(e.id_user AS BIGINT) AS id_user,
        JSON_TUPLE(e.event_properties, 'house_id', 'business_context'),
        e.ts_event AS ts_visit_intent,
        year,
        month,
        day
    FROM 
        datalake_amplitude_clean.events AS e
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
        AND e.id_app = 170698
        AND e.event_type IN ('visit_intent_clicked','visit_schedule_clicked', 'schedule_page_viewed', 'visit_schedule_confirmed')
        AND e.id_user IS NOT NULL 
)
SELECT
    id_user,
    CAST(TRIM(c0) AS BIGINT) AS id_house,
    ts_visit_intent,
    year,
    month,
    day
FROM
    aux_events
WHERE
    TRIM(c1) IN ('sale','SALE')