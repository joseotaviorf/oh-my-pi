SELECT
    CAST(e.id_user AS BIGINT) AS id_user,
    CAST(e.id_app AS BIGINT) AS id_app,
    CAST(TRIM(GET_JSON_OBJECT(e.event_properties, '$.house_id')) AS BIGINT) AS id_house,
    CAST(e.ts_event AS TIMESTAMP) AS ts_visit_intent
FROM 
    datalake_amplitude_clean.events AS e
WHERE
    e.event_type IN ('visit_intent_clicked','visit_schedule_clicked', 'schedule_page_viewed', 'visit_schedule_confirmed')
    AND CAST(TRIM(GET_JSON_OBJECT(event_properties, '$.business_context')) AS STRING) IN ('sale','SALE')
    AND e.id_app = 170698
    AND CAST(e.ts_event AS DATE) >= CAST('2020-01-01' AS DATE)
    AND e.id_user IS NOT NULL 