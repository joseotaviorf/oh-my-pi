SELECT
    id_user_braze,
    id_canvas,
    id_campaign,
    event_type,
    event_channel,
    event_action,
    'owner' AS user_type,
    COUNT(DISTINCT id_event) AS event_count,
    DATE(ts_event) AS dt_event
FROM
    datalake_braze.events_owners
GROUP BY 1,2,3,4,5,6,7,8
UNION
SELECT
    id_user_braze,
    id_canvas,
    id_campaign,
    event_type,
    event_channel,
    event_action,
    'tenant' AS user_type,
    COUNT(DISTINCT id_event) AS event_count,
    DATE(ts_event) AS dt_event
FROM
    datalake_braze.events_tenants
GROUP BY 1,2,3,4,5,6,7,8
