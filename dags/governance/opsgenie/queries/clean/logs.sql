SELECT 
    id,
    log,    
    offset AS event_offset,
    owner AS event_owner,
    type AS event_type,
    REGEXP_LIKE(log,r'Sent \[email\] notification to') AS is_email_notification_sent,
    REGEXP_LIKE(log,r'Sent \[voice\] notification to') AS is_call_notification_made,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_opsgenie_raw.logs
WHERE
    DATE(created_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')