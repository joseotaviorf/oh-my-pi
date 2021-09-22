SELECT
    ea.id_user_dispatch,
    ea.id_user_braze,
    ea.id_user,
    ea.event_channel,
    impression_affiliates.ts_event AS ts_inapp_impressioned,
--  click_affiliates.ts_event AS ts_inapp_clicked,
    ea.year,
    ea.month,
    ea.day
FROM 
    datalake_braze.events_affiliates AS ea
LEFT JOIN
    datalake_braze.events_affiliates AS impression_affiliates
        ON ea.id_user_dispatch = impression_affiliates.id_user_dispatch
        AND impression_affiliates.event_type = 'users.messages.inappmessage.Impression'
-- LEFT JOIN
--  datalake_braze.events_affiliates AS click_affiliates
--      ON ea.id_user_dispatch = click_affiliates.id_user_dispatch
--      AND click_affiliates.event_type = 'users.messages.inappmessage.Click'
WHERE
    ea.event_channel = 'inappmessage'
    AND ea.year = {year}
    AND ea.month = {month}
    AND ea.day = {day}
GROUP BY
    1,2,3,4,5,6,7,8