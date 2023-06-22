SELECT
    id AS id_subscription,
    user_campaign_preferences,
    whatsapp, 
    email,
    push,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_notify_me_raw.subscriptions
WHERE
	DATE(updated_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')