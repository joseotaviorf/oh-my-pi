SELECT
    id AS id_user_campaign_preferences,
    user_id AS id_user,
    user_id_mod AS mod_id_user,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    campaign_name,
    campaign_name_mod AS mod_campaign_name,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_notify_me_raw.user_campaign_preferences_aud
WHERE
	DATE(updated_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')