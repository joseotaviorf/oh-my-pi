SELECT
    id AS id_subscription,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    user_campaign_preferences,
    user_campaign_preferences_mod AS mod_user_campaign_preferences,
    whatsapp, 
    whatsapp_mod AS mod_whatsapp, 
    email,
    email_mod AS mod_email,
    push,
    push_mod AS mod_push,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_notify_me_raw.subscriptions_aud
WHERE
	DATE(updated_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')