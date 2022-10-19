SELECT
    ea.id_user_dispatch,
    ea.id_user_braze,
    ea.id_user,
    ea.event_channel,
    send_affiliates.ts_event AS ts_push_sent,
    open_affiliates.ts_event AS ts_push_opened,
    bounce_affiliates.ts_event AS ts_push_bounced,
    ea.year,
    ea.month,
    ea.day
FROM
    datalake_braze.events_affiliates AS ea
LEFT JOIN
    datalake_braze.events_affiliates AS send_affiliates
        ON ea.id_user_dispatch = send_affiliates.id_user_dispatch
        AND send_affiliates.event_type = 'users.messages.pushnotification.Send'
LEFT JOIN
    datalake_braze.events_affiliates AS open_affiliates
        ON ea.id_user_dispatch = open_affiliates.id_user_dispatch
        AND open_affiliates.event_type = 'users.messages.pushnotification.Open'
LEFT JOIN
    datalake_braze.events_affiliates AS bounce_affiliates
        ON ea.id_user_dispatch = bounce_affiliates.id_user_dispatch
        AND bounce_affiliates.event_type = 'users.messages.pushnotification.Bounce'
WHERE
    ea.event_channel = 'pushnotification'
    AND ea.year = {year}
    AND ea.month = {month}
    AND ea.day = {day}
GROUP BY
    1,2,3,4,5,6,7,8,9,10