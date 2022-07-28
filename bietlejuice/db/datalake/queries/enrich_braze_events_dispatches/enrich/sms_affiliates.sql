SELECT
    ea.id_user_dispatch,
    ea.id_user_braze,
    ea.id_user,
    ea.event_channel,
    send_affiliates.ts_event AS ts_sms_sent,
    sendtocarrier_affiliates.ts_event AS ts_sms_send_to_carried,
    delivery_affiliates.ts_event AS ts_sms_delivered,
    rejection_affiliates.ts_event AS ts_sms_rejected,
    deliveryfailure_affiliates.ts_event AS ts_sms_delivery_failed,
    ea.year,
    ea.month,
    ea.day
FROM 
    datalake_braze.events_affiliates AS ea
LEFT JOIN
    datalake_braze.events_affiliates AS send_affiliates
        ON ea.id_user_dispatch = send_affiliates.id_user_dispatch 
        AND send_affiliates.event_type = 'users.messages.sms.Send'
LEFT JOIN
    datalake_braze.events_affiliates AS sendtocarrier_affiliates
        ON ea.id_user_dispatch = sendtocarrier_affiliates.id_user_dispatch 
        AND sendtocarrier_affiliates.event_type = 'users.messages.sms.SendToCarrier'
LEFT JOIN
    datalake_braze.events_affiliates AS delivery_affiliates
        ON ea.id_user_dispatch = delivery_affiliates.id_user_dispatch
        AND delivery_affiliates.event_type = 'users.messages.sms.Delivery'
LEFT JOIN
    datalake_braze.events_affiliates AS rejection_affiliates
        ON ea.id_user_dispatch = rejection_affiliates.id_user_dispatch
        AND rejection_affiliates.event_type = 'users.messages.sms.Rejection'
LEFT JOIN
    datalake_braze.events_affiliates AS deliveryfailure_affiliates
        ON ea.id_user_dispatch = deliveryfailure_affiliates.id_user_dispatch
        AND deliveryfailure_affiliates.event_type = 'users.messages.sms.DeliveryFailure'
WHERE
    ea.event_channel = 'sms'
    AND ea.year = {year}
    AND ea.month = {month}
    AND ea.day = {day}
GROUP BY
    1,2,3,4,5,6,7,8,9,10,11,12