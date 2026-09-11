-- Broadcast the day's id_user_dispatch keys into each dispatch table so
-- EMR hash-joins ~1M keys instead of shuffling the full dispatch history.
-- Do not filter dispatch tables by year/month/day: matching rows live in
-- older partitions and must be kept for the same DISTINCT output.
-- join_salt + REPARTITION spreads a hot id_user_dispatch across write tasks
-- without changing LEFT JOIN / DISTINCT semantics.
WITH events_tenants_day AS (
    SELECT
        et.id_user_dispatch,
        et.id_user_braze,
        et.id_user,
        et.id_campaign,
        et.id_variant_campaign,
        et.id_canvas,
        et.id_variant_canvas,
        et.id_step_canvas,
        et.event_channel,
        et.year,
        et.month,
        et.day
    FROM
        datalake_braze.events_tenants AS et
    WHERE
        et.year = {year}
        AND et.month = {month}
        AND et.day = {day}
),
dispatch_keys AS (
    SELECT DISTINCT
        events_tenants_day.id_user_dispatch
    FROM
        events_tenants_day
),
email_tenants AS (
    SELECT /*+ BROADCAST(dispatch_keys) */
        email.id_user_dispatch,
        email.ts_email_sent,
        email.ts_email_delivered,
        email.ts_email_opened,
        email.ts_email_clicked,
        email.ts_email_bounced,
        email.ts_email_spammed,
        email.ts_email_unsubscribed
    FROM
        datalake_braze_dispatches.email_tenants AS email
    INNER JOIN
        dispatch_keys
            ON dispatch_keys.id_user_dispatch = email.id_user_dispatch
    WHERE
        email.event_channel = 'email'
),
push_tenants AS (
    SELECT /*+ BROADCAST(dispatch_keys) */
        push.id_user_dispatch,
        push.ts_push_sent,
        push.ts_push_opened,
        push.ts_push_bounced
    FROM
        datalake_braze_dispatches.push_tenants AS push
    INNER JOIN
        dispatch_keys
            ON dispatch_keys.id_user_dispatch = push.id_user_dispatch
    WHERE
        push.event_channel = 'pushnotification'
),
webhook_tenants AS (
    SELECT /*+ BROADCAST(dispatch_keys) */
        webhook.id_user_dispatch,
        webhook.ts_webhook_sent
    FROM
        datalake_braze_dispatches.webhook_tenants AS webhook
    INNER JOIN
        dispatch_keys
            ON dispatch_keys.id_user_dispatch = webhook.id_user_dispatch
    WHERE
        webhook.event_channel = 'webhook'
),
inapp_tenants AS (
    SELECT /*+ BROADCAST(dispatch_keys) */
        inapp.id_user_dispatch,
        inapp.ts_inapp_impressioned
    FROM
        datalake_braze_dispatches.inapp_tenants AS inapp
    INNER JOIN
        dispatch_keys
            ON dispatch_keys.id_user_dispatch = inapp.id_user_dispatch
    WHERE
        inapp.event_channel = 'inappmessage'
),
sms_tenants AS (
    SELECT /*+ BROADCAST(dispatch_keys) */
        sms.id_user_dispatch,
        sms.ts_sms_sent,
        sms.ts_sms_send_to_carried,
        sms.ts_sms_delivered,
        sms.ts_sms_rejected,
        sms.ts_sms_delivery_failed
    FROM
        datalake_braze_dispatches.sms_tenants AS sms
    INNER JOIN
        dispatch_keys
            ON dispatch_keys.id_user_dispatch = sms.id_user_dispatch
    WHERE
        sms.event_channel = 'sms'
),
-- Hash-partition joined rows by (id, timestamps, row id) so a hot id_user_dispatch
-- does not land in a single DISTINCT/write task. join_salt is not in the output.
joined_tenants AS (
    SELECT
        et.id_user_dispatch,
        et.id_user_braze,
        et.id_user,
        et.id_campaign,
        et.id_variant_campaign,
        et.id_canvas,
        et.id_variant_canvas,
        et.id_step_canvas,
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
        et.year,
        et.month,
        et.day,
        PMOD(
            XXHASH64(
                et.id_user_dispatch,
                email_tenants.ts_email_sent,
                webhook_tenants.ts_webhook_sent,
                MONOTONICALLY_INCREASING_ID()
            ),
            16
        ) AS join_salt
    FROM
        events_tenants_day AS et
    LEFT JOIN
        email_tenants
            ON email_tenants.id_user_dispatch = et.id_user_dispatch
    LEFT JOIN
        push_tenants
            ON push_tenants.id_user_dispatch = et.id_user_dispatch
    LEFT JOIN
        webhook_tenants
            ON webhook_tenants.id_user_dispatch = et.id_user_dispatch
    LEFT JOIN
        inapp_tenants
            ON inapp_tenants.id_user_dispatch = et.id_user_dispatch
    LEFT JOIN
        sms_tenants
            ON sms_tenants.id_user_dispatch = et.id_user_dispatch
),
spread_tenants AS (
    SELECT /*+ REPARTITION(800, id_user_dispatch, join_salt) */
        joined_tenants.id_user_dispatch,
        joined_tenants.id_user_braze,
        joined_tenants.id_user,
        joined_tenants.id_campaign,
        joined_tenants.id_variant_campaign,
        joined_tenants.id_canvas,
        joined_tenants.id_variant_canvas,
        joined_tenants.id_step_canvas,
        joined_tenants.event_channel,
        joined_tenants.ts_email_sent,
        joined_tenants.ts_email_delivered,
        joined_tenants.ts_email_opened,
        joined_tenants.ts_email_clicked,
        joined_tenants.ts_email_bounced,
        joined_tenants.ts_email_spammed,
        joined_tenants.ts_email_unsubscribed,
        joined_tenants.ts_push_sent,
        joined_tenants.ts_push_opened,
        joined_tenants.ts_push_bounced,
        joined_tenants.ts_webhook_sent,
        joined_tenants.ts_inapp_impressioned,
        joined_tenants.ts_sms_sent,
        joined_tenants.ts_sms_send_to_carried,
        joined_tenants.ts_sms_delivered,
        joined_tenants.ts_sms_rejected,
        joined_tenants.ts_sms_delivery_failed,
        joined_tenants.year,
        joined_tenants.month,
        joined_tenants.day
    FROM
        joined_tenants
)
SELECT DISTINCT
    spread_tenants.id_user_dispatch,
    spread_tenants.id_user_braze,
    spread_tenants.id_user,
    spread_tenants.id_campaign,
    spread_tenants.id_variant_campaign,
    spread_tenants.id_canvas,
    spread_tenants.id_variant_canvas,
    spread_tenants.id_step_canvas,
    'tenants' AS user_type,
    spread_tenants.event_channel,
    spread_tenants.ts_email_sent,
    spread_tenants.ts_email_delivered,
    spread_tenants.ts_email_opened,
    spread_tenants.ts_email_clicked,
    spread_tenants.ts_email_bounced,
    spread_tenants.ts_email_spammed,
    spread_tenants.ts_email_unsubscribed,
    spread_tenants.ts_push_sent,
    spread_tenants.ts_push_opened,
    spread_tenants.ts_push_bounced,
    spread_tenants.ts_webhook_sent,
    spread_tenants.ts_inapp_impressioned,
    spread_tenants.ts_sms_sent,
    spread_tenants.ts_sms_send_to_carried,
    spread_tenants.ts_sms_delivered,
    spread_tenants.ts_sms_rejected,
    spread_tenants.ts_sms_delivery_failed,
    spread_tenants.year,
    spread_tenants.month,
    spread_tenants.day
FROM
    spread_tenants
