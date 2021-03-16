SELECT
  ueat.id_user_braze AS sk_braze_user,
  SUM(uetw.total_campaigns_sent_to) AS total_campaigns_sent_to_this_week,
  SUM(uelw.total_campaigns_sent_to) AS total_campaigns_sent_to_last_week,
  SUM(ue2w.total_campaigns_sent_to) AS total_campaigns_sent_to_2w_ago,
  SUM(ue3w.total_campaigns_sent_to) AS total_campaigns_sent_to_3w_ago,
  SUM(ueat.total_campaigns_sent_to) AS total_campaigns_sent_to_all_time,
  SUM(uetw.total_canvases_sent_to) AS total_canvases_sent_to_this_week,
  SUM(uelw.total_canvases_sent_to) AS total_canvases_sent_to_last_week,
  SUM(ue2w.total_canvases_sent_to) AS total_canvases_sent_to_2w_ago,
  SUM(ue3w.total_canvases_sent_to) AS total_canvases_sent_to_3w_ago,
  SUM(ueat.total_canvases_sent_to) AS total_canvases_sent_to_all_time,
  SUM(uetw.total_tenant_communications_sent_to) AS total_tenant_communications_sent_to_this_week,
  SUM(uelw.total_tenant_communications_sent_to) AS total_tenant_communications_sent_to_last_week,
  SUM(ue2w.total_tenant_communications_sent_to) AS total_tenant_communications_sent_to_2w_ago,
  SUM(ue3w.total_tenant_communications_sent_to) AS total_tenant_communications_sent_to_3w_ago,
  SUM(ueat.total_tenant_communications_sent_to) AS total_tenant_communications_sent_to_all_time,
  SUM(uetw.total_owner_communications_sent_to) AS total_owner_communications_sent_to_this_week,
  SUM(uelw.total_owner_communications_sent_to) AS total_owner_communications_sent_to_last_week,
  SUM(ue2w.total_owner_communications_sent_to) AS total_owner_communications_sent_to_2w_ago,
  SUM(ue3w.total_owner_communications_sent_to) AS total_owner_communications_sent_to_3w_ago,
  SUM(ueat.total_owner_communications_sent_to) AS total_owner_communications_sent_to_all_time,
  SUM(uetw.total_emails_sent_to) AS total_emails_sent_to_this_week,
  SUM(uelw.total_emails_sent_to) AS total_emails_sent_to_last_week,
  SUM(ue2w.total_emails_sent_to) AS total_emails_sent_to_2w_ago,
  SUM(ue3w.total_emails_sent_to) AS total_emails_sent_to_3w_ago,
  SUM(ueat.total_emails_sent_to) AS total_emails_sent_to_all_time,
  SUM(uetw.total_emails_delivered_to) AS total_emails_delivered_to_this_week,
  SUM(uelw.total_emails_delivered_to) AS total_emails_delivered_to_last_week,
  SUM(ue2w.total_emails_delivered_to) AS total_emails_delivered_to_2w_ago,
  SUM(ue3w.total_emails_delivered_to) AS total_emails_delivered_to_3w_ago,
  SUM(ueat.total_emails_delivered_to) AS total_emails_delivered_to_all_time,
  SUM(uetw.total_email_opens) AS total_email_opens_this_week,
  SUM(uelw.total_email_opens) AS total_email_opens_last_week,
  SUM(ue2w.total_email_opens) AS total_email_opens_2w_ago,
  SUM(ue3w.total_email_opens) AS total_email_opens_3w_ago,
  SUM(ueat.total_email_opens) AS total_email_opens_all_time,
  SUM(uetw.total_email_clicks) AS total_email_clicks_this_week,
  SUM(uelw.total_email_clicks) AS total_email_clicks_last_week,
  SUM(ue2w.total_email_clicks) AS total_email_clicks_2w_ago,
  SUM(ue3w.total_email_clicks) AS total_email_clicks_3w_ago,
  SUM(ueat.total_email_clicks) AS total_email_clicks_all_time,
  SUM(uetw.total_push_notifications_sent_to) AS total_push_notifications_sent_to_this_week,
  SUM(uelw.total_push_notifications_sent_to) AS total_push_notifications_sent_to_last_week,
  SUM(ue2w.total_push_notifications_sent_to) AS total_push_notifications_sent_to_2w_ago,
  SUM(ue3w.total_push_notifications_sent_to) AS total_push_notifications_sent_to_3w_ago,
  SUM(ueat.total_push_notifications_sent_to) AS total_push_notifications_sent_to_all_time,
  SUM(uetw.total_push_notification_opens) AS total_push_notification_opens_this_week,
  SUM(uelw.total_push_notification_opens) AS total_push_notification_opens_last_week,
  SUM(ue2w.total_push_notification_opens) AS total_push_notification_opens_2w_ago,
  SUM(ue3w.total_push_notification_opens) AS total_push_notification_opens_3w_ago,
  SUM(ueat.total_push_notification_opens) AS total_push_notification_opens_all_time,
  SUM(uetw.total_inapp_message_views) AS total_inapp_message_views_this_week,
  SUM(uelw.total_inapp_message_views) AS total_inapp_message_views_last_week,
  SUM(ue2w.total_inapp_message_views) AS total_inapp_message_views_2w_ago,
  SUM(ue3w.total_inapp_message_views) AS total_inapp_message_views_3w_ago,
  SUM(ueat.total_inapp_message_views) AS total_inapp_message_views_all_time,
  SUM(uetw.total_inapp_message_clicks) AS total_inapp_message_clicks_this_week,
  SUM(uelw.total_inapp_message_clicks) AS total_inapp_message_clicks_last_week,
  SUM(ue2w.total_inapp_message_clicks) AS total_inapp_message_clicks_2w_ago,
  SUM(ue3w.total_inapp_message_clicks) AS total_inapp_message_clicks_3w_ago,
  SUM(ueat.total_inapp_message_clicks) AS total_inapp_message_clicks_all_time,
  SUM(uetw.total_webhooks_sent_to) AS total_webhooks_sent_to_this_week,
  SUM(uelw.total_webhooks_sent_to) AS total_webhooks_sent_to_last_week,
  SUM(ue2w.total_webhooks_sent_to) AS total_webhooks_sent_to_2w_ago,
  SUM(ue3w.total_webhooks_sent_to) AS total_webhooks_sent_to_3w_ago,
  SUM(ueat.total_webhooks_sent_to) AS total_webhooks_sent_to_all_time,
  SUM(uetw.total_sms_sent_to) AS total_sms_sent_to_this_week,
  SUM(uelw.total_sms_sent_to) AS total_sms_sent_to_last_week,
  SUM(ue2w.total_sms_sent_to) AS total_sms_sent_to_2w_ago,
  SUM(ue3w.total_sms_sent_to) AS total_sms_sent_to_3w_ago,
  SUM(ueat.total_sms_sent_to) AS total_sms_sent_to_all_time,
  SUM(uetw.total_sms_delivered_to) AS total_sms_delivered_to_this_week,
  SUM(uelw.total_sms_delivered_to) AS total_sms_delivered_to_last_week,
  SUM(ue2w.total_sms_delivered_to) AS total_sms_delivered_to_2w_ago,
  SUM(ue3w.total_sms_delivered_to) AS total_sms_delivered_to_3w_ago,
  SUM(ueat.total_sms_delivered_to) AS total_sms_delivered_to_all_time,
  MAX(ueat.dt_last_campaign_sent_to) AS dt_last_campaign_sent_to,
  MAX(ueat.dt_last_canvas_sent_to) AS dt_last_canvas_sent_to,
  MAX(ueat.dt_last_email_sent_to) AS dt_last_email_sent_to,
  MAX(ueat.dt_last_email_delivered_to) AS dt_last_email_delivered_to,
  MAX(ueat.dt_last_email_opened) AS dt_last_email_opened,
  MAX(ueat.dt_last_email_clicked) AS dt_last_email_clicked,
  MAX(ueat.dt_last_push_notification_sent_to) AS dt_last_push_notification_sent_to,
  MAX(ueat.dt_last_push_notification_opened) AS dt_last_push_notification_opened,
  MAX(ueat.dt_last_inapp_message_sent_to) AS dt_last_inapp_message_sent_to,
  MAX(ueat.dt_last_inapp_message_clicked) AS dt_last_inapp_message_clicked,
  MAX(ueat.dt_last_webhook_sent_to) AS dt_last_webhook_sent_to,
  MAX(ueat.dt_last_sms_sent_to) AS dt_last_sms_sent_to,
  MAX(ueat.dt_last_sms_delivered_to) AS dt_last_sms_delivered_to,
  NOW() AS ts_load,
  ueat.year,
  ueat.month,
  ueat.day
FROM
    datalake_braze_user_centric_periodicity.user_events_all_time AS ueat
LEFT JOIN
    datalake_braze_user_centric_periodicity.user_events_this_week AS uetw
        ON uetw.id_user_braze = ueat.id_user_braze
        AND uetw.year = ueat.year
        AND uetw.month = ueat.month
        AND uetw.day = ueat.day
LEFT JOIN
    datalake_braze_user_centric_periodicity.user_events_last_week AS uelw
        ON uelw.id_user_braze = ueat.id_user_braze
        AND uelw.year = ueat.year
        AND uelw.month = ueat.month
        AND uelw.day = ueat.day
LEFT JOIN
    datalake_braze_user_centric_periodicity.user_events_2w_ago AS ue2w
        ON ue2w.id_user_braze = ueat.id_user_braze
        AND ue2w.year = ueat.year
        AND ue2w.month = ueat.month
        AND ue2w.day = ueat.day
LEFT JOIN
    datalake_braze_user_centric_periodicity.user_events_3w_ago AS ue3w
        ON ue3w.id_user_braze = ueat.id_user_braze
        AND ue3w.year = ueat.year
        AND ue3w.month = ueat.month
        AND ue3w.day = ueat.day
WHERE
    ueat.year = {year}
    AND ueat.month = {month}
    AND ueat.day = {day}
GROUP BY 1,91,92,93
