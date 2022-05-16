WITH aux AS (
    SELECT
        *,
        CAST(GET_JSON_OBJECT(event_properties, '$.house_id') AS BIGINT) AS ep_house_id,
        GET_JSON_OBJECT(event_properties, '$.alert_target_date') AS ep_alert_target_date,
        CAST(COALESCE(GET_JSON_OBJECT(event_properties, '$.alert_slot_from'), '') AS BIGINT) AS ep_alert_slot_from,
        CAST(COALESCE(GET_JSON_OBJECT(event_properties, '$.alert_slot_to'), '') AS BIGINT) AS ep_alert_slot_to
    FROM
        datalake_amplitude_clean_staging.170698_visit_hoursalert_confirmed_events
    WHERE
        year={} 
        AND month={}
        AND day={} 
)
SELECT *,
    GET_JSON_OBJECT(event_properties, '$.business_context') AS ep_business_context,
    COALESCE(
        DATE(ep_alert_target_date),
        TO_DATE(SUBSTRING(ep_alert_target_date, 6, 11), 'dd MMM yyyy')
    ) AS dt_alert_target
FROM
    aux