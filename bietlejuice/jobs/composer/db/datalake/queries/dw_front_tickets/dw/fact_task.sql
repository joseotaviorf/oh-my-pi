WITH call_tasks AS (
    SELECT
        CAST(c.id_ticket AS BIGINT) AS sk_ticket,
        id_reservation AS sk_task,
        id_agent AS sk_agent,
        MD5(department) AS sk_department,
        MD5(concat('call', tags, direction)) AS sk_channel,
        department,
        'call' AS channel,
        sla_achieved AS is_sla,
        is_first_task,
        is_last_task,
        ts_task_created AS ts_started,
        ts_task_closed AS ts_closed
    FROM
        datalake_front_tickets.call c
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
),
chat_tasks AS (
    SELECT 
        CAST(c.id_ticket AS BIGINT) AS sk_ticket,
        id_task AS sk_task,
        id_agent AS sk_agent,
        MD5(department) AS sk_department,
        MD5(concat('chat', tags)) AS sk_channel,
        department,
        'chat' AS channel,
        sla_achieved AS is_sla,
        is_last_task,
        is_first_task,
        ts_task_created AS ts_started,
        ts_task_closed AS ts_closed
    FROM 
        datalake_front_tickets.chat c
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
),
email_tasks AS (
    SELECT 
        CAST(id_ticket AS BIGINT) AS sk_ticket,
        id_ticket AS sk_task,
        id_agent AS sk_agent,
        MD5(department) AS sk_department,
        MD5(concat('email', tags)) AS sk_channel,
        department,
        'email' AS channel,
        is_sla,
        TRUE AS is_first_task,
        TRUE AS is_last_task,
        ts_ticket_started AS ts_started,
        ts_ticket_ended AS ts_closed
    FROM 
        datalake_front_tickets.email
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
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