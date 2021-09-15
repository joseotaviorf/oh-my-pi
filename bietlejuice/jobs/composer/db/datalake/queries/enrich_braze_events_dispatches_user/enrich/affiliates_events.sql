SELECT DISTINCT
    ea.id_user_dispatch,
    ea.id_user_braze,
    ea.id_campaign,
    ea.id_variant_campaign,
    ea.id_canvas,
    ea.id_variant_canvas,
    ea.id_step_canvas,
    'affiliates' AS user_type,
    ea.event_channel,
    email_affiliates.ts_email_sent,
    email_affiliates.ts_email_delivered,
    email_affiliates.ts_email_opened,
    email_affiliates.ts_email_clicked,
    email_affiliates.ts_email_bounced,
    email_affiliates.ts_email_spammed,
    email_affiliates.ts_email_unsubscribed,
    push_affiliates.ts_push_sent,
    push_affiliates.ts_push_opened,
    push_affiliates.ts_push_bounced,
    webhook_affiliates.ts_webhook_sent,
    inapp_affiliates.ts_inapp_impressioned,
    sms_affiliates.ts_sms_sent,
    sms_affiliates.ts_sms_send_to_carried,
    sms_affiliates.ts_sms_delivered,
    sms_affiliates.ts_sms_rejected,
    sms_affiliates.ts_sms_delivery_failed,
    ea.year,
    ea.month,
    ea.day
FROM
    datalake_braze.events_affiliates AS ea
LEFT JOIN
    datalake_braze_dispatches.email_affiliates AS email_affiliates
        ON email_affiliates.id_user_dispatch = ea.id_user_dispatch
LEFT JOIN
    datalake_braze_dispatches.push_affiliates AS push_affiliates
        ON push_affiliates.id_user_dispatch = ea.id_user_dispatch
LEFT JOIN
    datalake_braze_dispatches.webhook_affiliates AS webhook_affiliates
        ON webhook_affiliates.id_user_dispatch = ea.id_user_dispatch
LEFT JOIN
    datalake_braze_dispatches.inapp_affiliates AS inapp_affiliates
        ON inapp_affiliates.id_user_dispatch = ea.id_user_dispatch
LEFT JOIN
    datalake_braze_dispatches.sms_affiliates AS sms_affiliates
        ON sms_affiliates.id_user_dispatch = ea.id_user_dispatch
WHERE
    ea.year = {year}
    AND ea.month = {month}
    AND ea.day = {day}