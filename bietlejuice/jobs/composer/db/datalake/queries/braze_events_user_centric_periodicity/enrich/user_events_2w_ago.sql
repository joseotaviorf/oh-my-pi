SELECT
  id_user_braze,
  SUM(
    CASE
      WHEN id_campaign IS NOT NULL
        AND event_action = 'send' THEN event_count
      ELSE 0
    END
  ) AS total_campaigns_sent_to,
  SUM(
    CASE
      WHEN id_canvas IS NOT NULL
        AND event_action = 'send' THEN event_count
      ELSE 0
    END
  ) AS total_canvases_sent_to,
  SUM(
    CASE
      WHEN user_type = 'tenant'
        AND event_action = 'send' THEN event_count
      ELSE 0
    END
  ) AS total_tenant_communications_sent_to,
  SUM(
    CASE
      WHEN user_type = 'owner'
        AND event_action = 'send' THEN event_count
      ELSE 0
    END
  ) AS total_owner_communications_sent_to,
  SUM(
    CASE
      WHEN event_channel = 'email'
        AND event_action = 'send' THEN event_count
      ELSE 0
    END
  ) AS total_emails_sent_to,
  SUM(
    CASE
      WHEN event_channel = 'email'
        AND event_action = 'delivery' THEN event_count
      ELSE 0
    END
  ) AS total_emails_delivered_to,
  SUM(
    CASE
      WHEN event_channel = 'email'
        AND event_action = 'open' THEN event_count
      ELSE 0
    END
  ) AS total_email_opens,
  SUM(
    CASE
      WHEN event_channel = 'email'
        AND event_action = 'click' THEN event_count
      ELSE 0
    END
  ) AS total_email_clicks,
  SUM(
    CASE
      WHEN event_channel = 'pushnotification'
        AND event_action = 'send' THEN event_count
      ELSE 0
    END
  ) AS total_push_notifications_sent_to,
  SUM(
    CASE
      WHEN event_channel = 'pushnotification'
        AND event_action = 'open' THEN event_count
      ELSE 0
    END
  ) AS total_push_notification_opens,
  SUM(
    CASE
      WHEN event_channel = 'inappmessage'
        AND event_action = 'impression' THEN event_count
      ELSE 0
    END
  ) AS total_inapp_message_views,
  SUM(
    CASE
      WHEN event_channel = 'inappmessage'
        AND event_action = 'click' THEN event_count
      ELSE 0
    END
  ) AS total_inapp_message_clicks,
  SUM(
    CASE
      WHEN event_channel = 'webhook'
        AND event_action = 'send' THEN event_count
      ELSE 0
    END
  ) AS total_webhooks_sent_to,
  SUM(
    CASE
      WHEN event_channel = 'sms'
        AND event_action = 'send' THEN event_count
      ELSE 0
    END
  ) AS total_sms_sent_to,
  SUM(
    CASE
      WHEN event_channel = 'sms'
        AND event_action = 'delivery' THEN event_count
      ELSE 0
    END
  ) AS total_sms_delivered_to,
  year,
  month,
  day
FROM
    datalake_braze_user_centric.user_events_daily
WHERE
    DATE_TRUNC('week',DATE(dt_event)) = DATE_TRUNC('week',DATE(CURRENT_DATE) - INTERVAL '14' DAY)
    AND year = {year}
    AND month = {month}
    AND day = {day}
GROUP by 1, 17, 18, 19
