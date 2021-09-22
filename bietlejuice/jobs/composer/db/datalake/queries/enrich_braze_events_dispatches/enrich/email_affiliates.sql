SELECT
    ea.id_user_dispatch,
    ea.id_user_braze,
    ea.id_user,
    ea.event_channel,
    send_affiliates.ts_event AS ts_email_sent,
    delivery_affiliates.ts_event AS ts_email_delivered,
    open_affiliates.ts_event AS ts_email_opened,
    click_affiliates.ts_event AS ts_email_clicked,
    bounce_affiliates.ts_event AS ts_email_bounced,
    spam_affiliates.ts_event AS ts_email_spammed,
    unsubscribe_affiliates.ts_event AS ts_email_unsubscribed,
    ea.year,
    ea.month,
    ea.day
FROM 
    datalake_braze.events_affiliates AS ea
LEFT JOIN
    datalake_braze.events_affiliates AS send_affiliates
        ON ea.id_user_dispatch = send_affiliates.id_user_dispatch
        AND send_affiliates.event_type = 'users.messages.email.Send'
LEFT JOIN
    datalake_braze.events_affiliates AS delivery_affiliates
        ON ea.id_user_dispatch = delivery_affiliates.id_user_dispatch
        AND delivery_affiliates.event_type = 'users.messages.email.Delivery'
LEFT JOIN
    datalake_braze.events_affiliates AS open_affiliates
        ON ea.id_user_dispatch = open_affiliates.id_user_dispatch
        AND open_affiliates.event_type = 'users.messages.email.Open'
LEFT JOIN
    datalake_braze.events_affiliates AS click_affiliates
        ON ea.id_user_dispatch = click_affiliates.id_user_dispatch
        AND click_affiliates.event_type = 'users.messages.email.Click'
LEFT JOIN
    datalake_braze.events_affiliates AS bounce_affiliates
        ON ea.id_user_dispatch = bounce_affiliates.id_user_dispatch
        AND bounce_affiliates.event_type IN ('users.messages.email.Bounce', 'users.messages.email.SoftBounce')
LEFT JOIN
    datalake_braze.events_affiliates AS spam_affiliates
        ON ea.id_user_dispatch = spam_affiliates.id_user_dispatch
        AND spam_affiliates.event_type = 'users.messages.email.MarkAsSpam'
LEFT JOIN
    datalake_braze.events_affiliates AS unsubscribe_affiliates
        ON ea.id_user_dispatch = unsubscribe_affiliates.id_user_dispatch
        AND unsubscribe_affiliates.event_type = 'users.messages.email.Unsubscribe'
WHERE
    ea.event_channel = 'email'
    AND ea.year = {year}
    AND ea.month = {month}
    AND ea.day = {day}
GROUP BY
    1,2,3,4,5,6,7,8,9,10,11,12,13,14