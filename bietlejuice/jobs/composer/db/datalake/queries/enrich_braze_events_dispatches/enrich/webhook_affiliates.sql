SELECT
    ea.id_user_dispatch,
    ea.id_user_braze,
    ea.id_user,
    ea.event_channel,
    send_affiliates.ts_event AS ts_webhook_sent,
    ea.year,
    ea.month,
    ea.day
FROM 
    datalake_braze.events_affiliates AS ea
LEFT JOIN
    datalake_braze.events_affiliates AS send_affiliates
        ON ea.id_user_dispatch = send_affiliates.id_user_dispatch
        AND send_affiliates.event_type = 'users.messages.webhook.Send'
WHERE
    ea.event_channel = 'webhook'
    AND ea.year = {year}
    AND ea.month = {month}
    AND ea.day = {day}
GROUP BY
    1,2,3,4,5,6,7,8