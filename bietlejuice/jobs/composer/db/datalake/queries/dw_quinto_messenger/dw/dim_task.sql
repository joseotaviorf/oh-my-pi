WITH completion_reason AS (
    SELECT
        id_task,
        task_queue_name,
        task_completion_reason
    FROM datalake_quinto_messenger.task_event
    WHERE task_completion_reason IS NOT NULL
    GROUP BY 1, 2, 3
),
twilio_date AS (
    SELECT 
        te.id_task,
        te.ts_twilio_created,
        te.ts_twilio_updated,
        te.ts_twilio_created_local,
        te.ts_twilio_updated_local
    FROM
        datalake_quinto_messenger.task_event te
    WHERE
        te.type = 'reservation.accepted'
)
SELECT
    t.id_task AS sk_task,
    t.channel_type_internal AS channel,
    cr.task_queue_name AS department,
    t.task_status AS status,
    cr.task_completion_reason AS completion_reason,
    t.customer_type_tag AS customer_type,
    t.contact_motivation_tag AS contact_motivation,
    t.contact_theme_tag AS contact_theme,
    t.ts_created,
    t.ts_updated,
    t.ts_created_local,
    t.ts_updated_local,
    td.ts_twilio_created,
    td.ts_twilio_updated,
    td.ts_twilio_created_local,
    td.ts_twilio_updated_local,
    NOW() AS ts_load
FROM 
    datalake_quinto_messenger.task t
LEFT JOIN
    twilio_date td
        ON t.id_task = td.id_task
LEFT JOIN 
    completion_reason cr
        ON cr.id_task = t.id_task