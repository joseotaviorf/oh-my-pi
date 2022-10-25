SELECT
    GET_JSON_OBJECT(REPLACE(_id, '$', ''), '$.oid') AS id,
    user_id AS id_user,
    GET_JSON_OBJECT(REPLACE(profile_id, '$', ''), '$.oid') AS id_profile,
    house_id AS id_house,
    house_ids AS ids_house,
    houses_ids AS ids_houses,
    lead_id AS id_lead,
    push_user_id AS id_push_user,
    quintoandar_id AS id_quintoandar,
    grandpa_user_id AS id_grandpa_user,
    device_id AS id_device,
    name,
    type,
    days,
    visit_code,
    business_context,
    cloudsearch_criteria,
    filters,
    houses_sent, 
    notifications_sent_agent,
    results, 
    source,
    BOOLEAN(active) AS is_active,
    BOOLEAN(is_auto_scheduling_possible) AS is_auto_scheduling_possible,
    DATE(date) AS dt_alert_triggered,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    CAST(GET_JSON_OBJECT(REPLACE(visit_day_time, '$', ''), '$.date') AS TIMESTAMP) AS ts_visited,
    TIMESTAMP(last_email_run) AS ts_last_email_run,
    CAST(GET_JSON_OBJECT(REPLACE(lastActivation, '$', ''), '$.date') AS TIMESTAMP) AS ts_last_activation,
    CAST(GET_JSON_OBJECT(REPLACE(last_day_sent, '$', ''), '$.date') AS TIMESTAMP) AS ts_last_day_sent,
    year,
    month,
    day
FROM
    datalake_cidade_alerta_raw.alert
WHERE
    year={year}
    AND month={month}
    AND day={day}
