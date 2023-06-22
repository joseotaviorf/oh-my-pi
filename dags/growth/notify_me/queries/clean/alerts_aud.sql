SELECT
    id,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    user_id AS id_user,
    user_id_mod AS mod_id_user,
    active,
    active_mod AS mod_active,
    campaign_name,
    campaign_name_mod AS mod_campaign_name,
    conditions,
    conditions_mod AS mod_conditions,
    processing_status,
    processing_status_mod AS mod_processing_status,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_notify_me_raw.alerts_aud
WHERE
	DATE(updated_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')