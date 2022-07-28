SELECT DISTINCT
    eo.id_user_dispatch,
    eo.id_user_braze,
    eo.id_user,
    eo.id_campaign,
    eo.id_variant_campaign,
    eo.id_canvas,
    eo.id_variant_canvas,
    eo.id_step_canvas,
    'owners' AS user_type,
    eo.event_channel,
    email_owners.ts_email_sent,
    email_owners.ts_email_delivered,
    email_owners.ts_email_opened,
    email_owners.ts_email_clicked,
    email_owners.ts_email_bounced,
    email_owners.ts_email_spammed,
    email_owners.ts_email_unsubscribed,
    push_owners.ts_push_sent,
    push_owners.ts_push_opened,
    push_owners.ts_push_bounced,
    webhook_owners.ts_webhook_sent,
    inapp_owners.ts_inapp_impressioned,
    sms_owners.ts_sms_sent,
    sms_owners.ts_sms_send_to_carried,
    sms_owners.ts_sms_delivered,
    sms_owners.ts_sms_rejected,
    sms_owners.ts_sms_delivery_failed,
    eo.year,
    eo.month,
    eo.day
FROM
    datalake_braze.events_owners AS eo
LEFT JOIN
    datalake_braze_dispatches.email_owners AS email_owners
        ON email_owners.id_user_dispatch = eo.id_user_dispatch
LEFT JOIN
    datalake_braze_dispatches.push_owners AS push_owners
        ON push_owners.id_user_dispatch = eo.id_user_dispatch
LEFT JOIN
    datalake_braze_dispatches.webhook_owners AS webhook_owners
        ON webhook_owners.id_user_dispatch = eo.id_user_dispatch
LEFT JOIN
    datalake_braze_dispatches.inapp_owners AS inapp_owners
        ON inapp_owners.id_user_dispatch = eo.id_user_dispatch
LEFT JOIN
    datalake_braze_dispatches.sms_owners AS sms_owners
        ON sms_owners.id_user_dispatch = eo.id_user_dispatch
WHERE
    eo.year = {year}
    AND eo.month = {month}
    AND eo.day = {day}
