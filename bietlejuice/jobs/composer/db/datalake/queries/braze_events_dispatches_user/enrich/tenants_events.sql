SELECT DISTINCT
    et.id_user_dispatch,
    et.id_user_braze,
    et.id_campaign,
    et.id_variant_campaign,
    et.id_canvas,
    et.id_variant_canvas,
    et.id_step_canvas,
    'tenants' AS user_type,
    et.event_channel,
    email_tenants.ts_email_sent,
    email_tenants.ts_email_delivered,
    email_tenants.ts_email_opened,
    email_tenants.ts_email_clicked,
    email_tenants.ts_email_bounced,
    email_tenants.ts_email_spammed,
    email_tenants.ts_email_unsubscribed,
    push_tenants.ts_push_sent,
    push_tenants.ts_push_opened,
    push_tenants.ts_push_bounced,
    webhook_tenants.ts_webhook_sent,
    inapp_tenants.ts_inapp_impressioned,
    sms_tenants.ts_sms_sent,
    sms_tenants.ts_sms_send_to_carried,
    sms_tenants.ts_sms_delivered,
    sms_tenants.ts_sms_rejected,
    sms_tenants.ts_sms_delivery_failed,
    eo.year,
    eo.month,
    eo.day
FROM
    datalake_braze.events_tenants AS et
LEFT JOIN
    datalake_braze_dispatches.email_tenants AS email_tenants
        ON email_tenants.id_user_dispatch = et.id_user_dispatch
LEFT JOIN
    datalake_braze_dispatches.push_tenants AS push_tenants
        ON push_tenants.id_user_dispatch = et.id_user_dispatch
LEFT JOIN
    datalake_braze_dispatches.webhook_tenants AS webhook_tenants
        ON webhook_tenants.id_user_dispatch = et.id_user_dispatch
LEFT JOIN
    datalake_braze_dispatches.inapp_tenants AS inapp_tenants
        ON inapp_tenants.id_user_dispatch = et.id_user_dispatch
LEFT JOIN
    datalake_braze_dispatches.sms_tenants AS sms_tenants
        ON sms_tenants.id_user_dispatch = et.id_user_dispatch
WHERE
    et.year = {year}
    AND et.month = {month}
    AND et.day = {day}
