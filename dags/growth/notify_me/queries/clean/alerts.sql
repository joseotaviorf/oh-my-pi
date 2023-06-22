SELECT
    id,
    user_id AS id_user,
    active,
    campaign_name,
    conditions,
    processing_status,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_notify_me_raw.alerts
WHERE
	DATE(updated_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')