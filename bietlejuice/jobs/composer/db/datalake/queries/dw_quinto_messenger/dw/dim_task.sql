WITH completion_reason AS (
    SELECT
        id_task,
        task_completion_reason
    FROM datalake_quinto_messenger.task_event
    WHERE task_completion_reason IS NOT NULL
    GROUP BY 1,2
)
SELECT
    t.id_task AS sk_task,
    t.channel_type_internal AS channel,
    t.ticket_group_name AS department,
    t.task_status AS status,
    cr.task_completion_reason AS completion_reason,
    t.customer_type_tag AS customer_type,
    t.contact_motivation_tag AS contact_motivation,
    t.contact_theme_tag AS contact_theme,
    t.ts_created,
    t.ts_updated
FROM datalake_quinto_messenger.task t
LEFT JOIN completion_reason cr
    ON cr.id_task = t.id_task
