WITH call_segments AS (
    SELECT
        CAST(c.id_ticket AS BIGINT) AS sk_ticket,
        id_segment AS sk_segment,
        id_agent AS sk_agent,
        MD5(department) AS sk_department,
        MD5(CONCAT('call', COALESCE(direction, ''))) AS sk_channel,
        id_external_service AS sk_external_service,
        department,
        transferred_from_dept,
        transferred_to_dept,
        transference_type,
        transference_reason,
        'call' AS channel,
        sla_achieved AS is_sla,
        is_first_segment,
        is_last_segment,
        ts_segment_created AS ts_started,
        ts_segment_closed AS ts_closed,
        NOW() AS ts_load
    FROM
        datalake_customer_support.call c
    WHERE
        id_segment IS NOT NULL
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17
),
chat_segments AS (
    SELECT 
        CAST(c.id_ticket AS BIGINT) AS sk_ticket,
        id_segment AS sk_segment,
        id_agent AS sk_agent,
        MD5(department) AS sk_department,
        MD5('chat') AS sk_channel,
        id_segment AS sk_external_service,
        department,
        transferred_from_dept,
        transferred_to_dept,
        transference_type,
        transference_reason,
        'chat' AS channel,
        sla_achieved AS is_sla,
        is_first_segment,
        is_last_segment,
        ts_segment_created AS ts_started,
        ts_segment_closed AS ts_closed,
        NOW() AS ts_load
    FROM 
        datalake_customer_support.chat c
    WHERE
        id_segment IS NOT NULL
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17
),
email_segments AS (
    SELECT 
        CAST(id_ticket AS BIGINT) AS sk_ticket,
        id_ticket AS sk_segment,
        id_agent AS sk_agent,
        MD5(department) AS sk_department,
        MD5('email') AS sk_channel,
        NULL AS sk_external_service,
        department,
        NULL AS transferred_from_dept,
        NULL AS transferred_to_dept,
        NULL AS transference_type,
        NULL AS transference_reason,
        'email' AS channel,
        is_sla,
        TRUE AS is_first_segment,
        TRUE AS is_last_segment,
        ts_ticket_started AS ts_started,
        ts_ticket_ended AS ts_closed,
        NOW() AS ts_load
    FROM 
        datalake_customer_support.email
    WHERE
        id_ticket IS NOT NULL
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17
)
SELECT
    *
FROM
    call_segments
UNION ALL
SELECT
    *
FROM
    chat_segments
UNION ALL
SELECT
    *
FROM
    email_segments
