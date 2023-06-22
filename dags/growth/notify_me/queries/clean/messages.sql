SELECT
    id AS id_message,
    alert_id AS id_alert,
    recipient,
    content,
    sent_at AS ts_sent,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_notify_me_raw.messages
WHERE
	DATE(updated_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')