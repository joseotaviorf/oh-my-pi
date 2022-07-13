WITH status_changes AS (
    SELECT
        id AS id_status_change,
        id_conversation,
        agent,
        channel,
        interaction_type,
        new_status,
        (BIGINT(ts_created) - BIGINT(LAG(ts_created) OVER (PARTITION BY id_conversation ORDER BY ts_created)))/60 AS status_time_minutes,
        ts_created,
        ts_load
    FROM
        datalake_stilingue.status_changes
),
first_answer AS (
    SELECT
        id_status_change,
        id_conversation,
        status_time_minutes,
        CASE
            WHEN status_time_minutes <= 180 THEN True
            ELSE False
        END AS is_sla_achieved,
        CASE 
            WHEN ROW_NUMBER() OVER(PARTITION BY id_conversation ORDER BY ts_created ASC) = 1 THEN TRUE
            ELSE FALSE
        END AS is_first_answer,
        ts_created
    FROM
        status_changes
    WHERE 
        new_status='Respondido'
),
answerable AS(
    SELECT
        i.id_conversation,
        i.conversation_status,
        DATE(DATE_TRUNC('WEEK', i.ts_load)) AS dt_week    
    FROM
        datalake_stilingue.interactions i
    LEFT JOIN
        datalake_quintoandar.aux_date a
        ON a.date = DATE(i.ts_load)
    WHERE
        a.weekend <> "Weekend"
        AND a.is_brz_holiday <> "Holiday"
        AND i.channel IN ('Twitter', 'Facebook', 'Instagram') 
        AND i.is_promoted IS FALSE 
        AND (
            i.tags LIKE '%04-CX- Reclamação%'
            OR i.tags LIKE '%05-CX-Engajamento%'
            OR i.tags LIKE '%03-CX-Dúvida-ou-Solicitação%'
        )
        AND i.interaction_type IN ('Menção', 'Inbox', 'Comentário')
    GROUP BY 1,2,3
)
SELECT
    i.id_conversation AS id_conversation,
    s.id_status_change AS id_interaction,
    s.agent,
    i.channel,
    i.interaction_type,
    COALESCE(s.new_status, i.conversation_status) AS status,
    s.status_time_minutes AS minutes_changed_status,
    CASE
        WHEN fa.is_first_answer IS TRUE THEN fa.is_sla_achieved
        ELSE NULL
    END AS is_sla_achieved,
    CASE
        WHEN fa.is_first_answer IS NOT NULL THEN fa.is_first_answer
        ELSE FALSE
    END AS is_first_answer,
    CASE
        WHEN a.id_conversation IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS is_answerable,
    CASE 
        WHEN a.conversation_status IN ('Ignorado', 'Respondido', 'Fechado') THEN TRUE 
        ELSE FALSE
    END AS is_handled,  
    COALESCE(a.dt_week, DATE(DATE_TRUNC('WEEK', s.ts_load)), DATE(DATE_TRUNC('WEEK', i.ts_load))) AS dt_week,
    COALESCE(s.ts_created, i.ts_posted) AS ts_created,
    COALESCE(s.ts_load, i.ts_load) AS ts_load
FROM 
    datalake_stilingue.interactions i
LEFT JOIN
    status_changes s
        ON i.id_conversation = s.id_conversation
LEFT JOIN
    first_answer fa
        ON s.id_status_change = fa.id_status_change
LEFT JOIN
    answerable a
        ON i.id_conversation = a.id_conversation