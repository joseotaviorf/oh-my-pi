SELECT
    id_user_braze,
    id_user,
    id_canvas,
    id_campaign,
    event_type,
    event_channel,
    event_action,
    'owner' AS user_type,
    COUNT(DISTINCT id_event) AS event_count,
    DATE(ts_event) AS dt_event,
    year,
    month,
    day
FROM
    datalake_braze.events_owners
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
GROUP BY 1,2,3,4,5,6,7,8,10,11,12,13
UNION
SELECT
    id_user_braze,
    id_user,
    id_canvas,
    id_campaign,
    event_type,
    event_channel,
    event_action,
    'tenant' AS user_type,
    COUNT(DISTINCT id_event) AS event_count,
    DATE(ts_event) AS dt_event,
    year,
    month,
    day
FROM
    datalake_braze.events_tenants
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
GROUP BY 1,2,3,4,5,6,7,8,10,11,12,13
UNION
SELECT
    id_user_braze,
    id_user,
    id_canvas,
    id_campaign,
    event_type,
    event_channel,
    event_action,
    'affiliate' AS user_type,
    COUNT(DISTINCT id_event) AS event_count,
    DATE(ts_event) AS dt_event,
    year,
    month,
    day
FROM
    datalake_braze.events_affiliates
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
GROUP BY 1,2,3,4,5,6,7,8,10,11,12,13