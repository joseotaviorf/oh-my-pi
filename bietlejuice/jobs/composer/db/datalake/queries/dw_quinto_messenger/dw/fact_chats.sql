WITH tasks AS (
    SELECT
        id_channel,
        COUNT(id_task) AS tasks
    FROM datalake_quinto_messenger.task
    GROUP BY 1
),
customer_identification AS (
    SELECT
        REGEXP_REPLACE(customer_contact,'(^(\\+55)|\\D)','') AS phone,
        MAX(id_user) AS id_user,
        MAX(cpf) AS cpf
    FROM datalake_ebdb_customer_contact_identification.customer_contact_identification
    WHERE channel = 'phone'
    GROUP BY 1
)
SELECT
    c.id_conversation AS sk_chat,
    c.id_source AS sk_session,
    COALESCE(ci.id_user,-1) AS sk_user,
    ci.cpf AS sk_personal_document,
    COALESCE(CAST(date_format(c.ts_created, 'yyyyMMdd') AS BIGINT), -1) AS sk_created_date,
    c.seconds_duration/60.0 AS minutes_duration,
    t.tasks
FROM datalake_quinto_messenger.channel c
LEFT JOIN tasks t
    ON t.id_channel = c.id_channel
LEFT JOIN customer_identification ci
    ON ci.phone = REGEXP_REPLACE(c.from_phone_number,'(^(\\+55)|\\D)','')
