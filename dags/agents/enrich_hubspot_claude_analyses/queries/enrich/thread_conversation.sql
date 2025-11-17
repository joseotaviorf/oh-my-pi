WITH threads AS (
    SELECT
        CAST(t.id_thread AS BIGINT) AS id_thread,
        CAST(t.id_inbox AS BIGINT) AS id_inbox,
        CAST(t.id_associated_contact AS BIGINT) AS id_associated_contact,
        CAST(GET_JSON_OBJECT(c.properties, '$.hubspot_owner_id') AS BIGINT) AS id_hubspot_owner,
        TRIM(
            COALESCE(GET_JSON_OBJECT(c.properties, '$.firstname'), '') 
            || ' ' || 
            COALESCE(GET_JSON_OBJECT(c.properties, '$.lastname'), '')
        ) AS associated_contact_name,
        GET_JSON_OBJECT(c.properties, '$.email') AS associated_contact_email,
        TRIM(
            COALESCE(o.first_name, '') 
            || ' ' || 
            COALESCE(o.last_name, '') 
        ) AS hubspot_owner_name,
        t.ts_created AS ts_thread_created,
        t.ts_latest_message_timestamp AS ts_thread_updated,
        YEAR(t.ts_created) AS year,
        MONTH(t.ts_created) AS month,
        DAY(t.ts_created) AS day
    FROM
        datalake_hubspot_clean.threads AS t
    LEFT JOIN
        datalake_hubspot_clean.contact AS c
            ON c.id_contact = t.id_associated_contact
            AND DATE(c.ts_created) <= DATE(t.ts_latest_message_timestamp)
    LEFT JOIN
        datalake_hubspot_clean.owner AS o
            ON o.id_owner = GET_JSON_OBJECT(c.properties, '$.hubspot_owner_id')
            AND o.is_archived IS FALSE
    WHERE
        DATE(t.ts_load) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    QUALIFY
        1 = ROW_NUMBER() OVER (
            PARTITION BY t.id_thread
            ORDER BY IF(o.id_owner IS NOT NULL, 1, 0) DESC, c.ts_updated DESC, t.ts_latest_message_timestamp DESC
        )
),
thread_messages AS (
    SELECT
        tm.id_thread_message,
        tm.id_thread_conversation,
        tm.direction,
        CASE
            WHEN tm.direction == 'INCOMING' THEN 'Contact'
            WHEN tm.direction == 'OUTGOING' THEN 'Agent/Bot'
            ELSE 'System'
        END AS sender_type,
        IF(TRIM(tm.text) = '', NULL, TRIM(tm.text)) AS message_text,
        COALESCE(GET_JSON_OBJECT(tm.status, '$.statustype'), 'SUCCESS') AS status,
        GET_JSON_OBJECT(GET_JSON_OBJECT(tm.status, '$.failuredetails'), '$.errormessage') AS status_failure_details,
        tm.senders,
        tm.attachments,
        tm.ts_created AS ts_message_created,
        tm.ts_updated AS ts_message_updated
    FROM
        datalake_hubspot_clean.thread_messages AS tm
    JOIN    
        threads AS t
            ON t.id_thread = CAST(tm.id_thread_conversation AS BIGINT)
    QUALIFY
        1 = ROW_NUMBER() OVER(PARTITION BY tm.id_thread_message ORDER BY tm.ts_updated DESC)
),
concat_message_url_attachments AS (
    SELECT
        tm.id_thread_message,
        COLLECT_LIST(GET_JSON_OBJECT(lv.attachment, '$.url')) AS url_attachments_list
    FROM 
        thread_messages AS tm
    LATERAL VIEW 
        EXPLODE(tm.attachments) lv AS attachment
    WHERE 
        GET_JSON_OBJECT(lv.attachment, '$.url') IS NOT NULL
    GROUP BY 1
),
message_sender_data AS (
    SELECT
        tm.id_thread_message,
        COALESCE(
            GET_JSON_OBJECT(lv.senders, '$.friendlyname'),
            GET_JSON_OBJECT(lv.senders, '$.name'),
            'Unknown'
        ) AS sender_name,
        COALESCE(GET_JSON_OBJECT(GET_JSON_OBJECT(lv.senders, '$.deliveryidentifier'), '$.value'), 'N/A') AS sender_number
    FROM 
        thread_messages AS tm
    LATERAL VIEW 
        EXPLODE(tm.senders) lv AS senders
)
SELECT
    t.id_thread,
    t.id_inbox,
    tm.id_thread_message,
    t.id_associated_contact,
    t.id_hubspot_owner,
    IF(t.associated_contact_name = '', NULL, t.associated_contact_name) AS contact_name,
    t.associated_contact_email AS contact_email,
    IF(t.hubspot_owner_name = '', NULL, t.hubspot_owner_name) AS owner_name,
    tm.direction,
    tm.sender_type,
    msd.sender_name,
    msd.sender_number,
    tm.message_text,
    tm.status,
    tm.status_failure_details,
    cmua.url_attachments_list AS attachments_list,
    t.ts_thread_created,
    t.ts_thread_updated,
    tm.ts_message_created,
    tm.ts_message_updated,
    t.year,
    t.month,
    t.day
FROM
    threads AS t
LEFT JOIN
    thread_messages AS tm
        ON tm.id_thread_conversation = t.id_thread
LEFT JOIN
    concat_message_url_attachments AS cmua
        ON cmua.id_thread_message = tm.id_thread_message
LEFT JOIN
    message_sender_data AS msd
        ON msd.id_thread_message = tm.id_thread_message