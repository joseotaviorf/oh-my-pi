SELECT DISTINCT
    documentId AS id,
    before AS original_message,
    after AS updated_message,
    eventType AS event_type,
    TIMESTAMP(FROM_UNIXTIME(BIGINT(GET_JSON_OBJECT(after, '$.notifications.emailSentToOwnerAt._seconds')), 'yyyy-MM-dd HH:mm:ss')) AS ts_email_sent_to_owner,
    CAST(timestamp AS TIMESTAMP) AS ts_updated,
    year,
    month, 
    day
FROM 
    datalake_firestore_raw.rent_offer
WHERE 
    year={year} 
    AND month={month} 
    AND day={day}