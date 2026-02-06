WITH base_comments AS (
    -- Esta CTE isola a lógica de junção e filtragem inicial
    SELECT DISTINCT
        tc.id_ticket,
        zu.role, 
        CAST(tc.ts_created AS TIMESTAMP) - INTERVAL '3' HOUR AS ts_comment,
        tc.body AS comment
    FROM
        datalake_zendesk_clean.ticket_comments AS tc
    LEFT JOIN datalake_support_users.zendesk_users AS zu 
        ON CAST(zu.id_user_zendesk AS STRING) = CAST(tc.id_author AS STRING)
    LEFT JOIN datalake_customer_support.tickets AS t 
        ON CAST(t.id_ticket AS STRING) = CAST(tc.id_ticket AS STRING)
    WHERE 
        tc.is_public = TRUE 
        AND t.ts_created >= DATE_SUB(CURRENT_DATE(), 13 * 30) 
)

SELECT
    id_ticket,
    ts_comment,
    role,
    -- Busca o timestamp do comentário anterior
    LAG(ts_comment, 1) OVER (PARTITION BY id_ticket ORDER BY ts_comment ASC) AS ts_previous_comment,
    -- Busca o papel (role) de quem comentou anteriormente
    LAG(role, 1) OVER (PARTITION BY id_ticket ORDER BY ts_comment ASC) AS previous_role,
    -- Calcula a diferença em segundos
    (UNIX_TIMESTAMP(ts_comment) - 
     UNIX_TIMESTAMP(LAG(ts_comment, 1) OVER (PARTITION BY id_ticket ORDER BY ts_comment ASC))) AS seconds_since_previous_comment,
    comment
FROM 
    base_comments
