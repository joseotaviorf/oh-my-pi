WITH call_tasks AS (
    SELECT
        CAST(c.id_ticket AS BIGINT) AS sk_ticket,
        id_reservation AS sk_task,
        id_agent AS sk_agent,
        MD5(department) AS sk_department,
        MD5(concat('call', tags, direction)) AS sk_channel,
        id_task AS sk_segment,
        department,
        transferred_from_dept,
        transferred_to_dept,
        transference_type,
        'call' AS channel,
        sla_achieved AS is_sla,
        is_first_task,
        is_last_task,
        ts_task_created AS ts_started,
        ts_task_closed AS ts_closed,
        NOW() AS ts_load
    FROM
        datalake_front_tickets.call c
    WHERE
        id_reservation IS NOT NULL
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16
),
chat_tasks AS (
    SELECT 
        CAST(c.id_ticket AS BIGINT) AS sk_ticket,
        id_task AS sk_task,
        id_agent AS sk_agent,
        MD5(department) AS sk_department,
        MD5(concat('chat', tags)) AS sk_channel,
        id_task AS sk_segment,
        department,
        transferred_from_dept,
        transferred_to_dept,
        transference_type,
        'chat' AS channel,
        sla_achieved AS is_sla,
        is_last_task,
        is_first_task,
        ts_task_created AS ts_started,
        ts_task_closed AS ts_closed,
        NOW() AS ts_load
    FROM 
        datalake_front_tickets.chat c
    WHERE
        id_task IS NOT NULL
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16
),
email_tasks AS (
    SELECT 
        CAST(id_ticket AS BIGINT) AS sk_ticket,
        id_ticket AS sk_task,
        id_agent AS sk_agent,
        MD5(department) AS sk_department,
        MD5(concat('email', tags)) AS sk_channel,
        NULL AS sk_segment,
        department,
        NULL AS transferred_from_dept,
        NULL AS transferred_to_dept,
        NULL AS transference_type,
        'email' AS channel,
        is_sla,
        TRUE AS is_first_task,
        TRUE AS is_last_task,
        ts_ticket_started AS ts_started,
        ts_ticket_ended AS ts_closed,
        NOW() AS ts_load
    FROM 
        datalake_front_tickets.email
    WHERE
        id_ticket IS NOT NULL
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16
)
SELECT
    *
FROM
    call_tasks
UNION ALL
SELECT
    *
FROM
    chat_tasks
UNION ALL
SELECT
    *
FROM
    email_tasks
