SELECT
    id AS id_message,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    alert_id AS id_alert,
    alert_id_mod AS mod_id_alert,
    recipient,
    recipient_mod AS mod_recipient,
    content,
    content_mod AS mod_content,
    sent_at AS ts_sent,
    sent_at_mod AS mod_ts_sent,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_notify_me_raw.messages_aud
WHERE
	DATE(updated_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')