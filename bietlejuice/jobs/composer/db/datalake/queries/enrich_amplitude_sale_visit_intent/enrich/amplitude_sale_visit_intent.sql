SELECT
    CAST(e.id_user AS BIGINT) AS id_user,
    CAST(TRIM(GET_JSON_OBJECT(e.event_properties, '$.house_id')) AS BIGINT) AS id_house,
    e.ts_event AS ts_visit_intent
FROM 
    datalake_amplitude_clean.events AS e
WHERE
    e.year >= 2020
    AND e.id_app = 170698
    AND e.event_type IN ('visit_intent_clicked','visit_schedule_clicked', 'schedule_page_viewed', 'visit_schedule_confirmed')
    AND CAST(TRIM(GET_JSON_OBJECT(event_properties, '$.business_context')) AS STRING) IN ('sale','SALE')
    AND e.id_user IS NOT NULL 