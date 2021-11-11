WITH chat_csat AS(
    SELECT
        c.id_ticket,
        sa.rating AS csat_score,
        c.group_name,
        sa.comment,
        CASE
            WHEN sa.is_solved = TRUE THEN TRUE
            WHEN sa.is_solved = FALSE THEN FALSE
            ELSE NULL
        END AS is_solved,
        CAST(c.ts_attended AS TIMESTAMP) AS ts_survey
    FROM
        datalake_chat_fup_clean.chats_chat c
    JOIN 
        datalake_chat_fup_clean.surveys_survey ss 
            ON ss.id_chat = c.id
    LEFT JOIN 
        datalake_chat_fup_clean.surveys_answer sa 
            ON ss.id = sa.id_survey
    WHERE
        sa.id IS NOT NULL
),
zendesk_aditional_ticket_info AS (
    SELECT DISTINCT 
        tf.id_ticket,
        c.id AS id_chat,
        COALESCE(GET_JSON_OBJECT(c.session, "$.id"), ftm.id_session) AS id_session,
        ftm.id_user,
        t.id_assignee,
        ftm.id_contract,
        tf.tags,
        tf.description,
        tf.status,
        tf.custom_fields,
        tf.group_name AS zendesk_ticket_department,
        ftm.minutes_first_resolution_calendar AS minutes_first_resolution_time_calendar,
        ftm.minutes_first_resolution_business AS minutes_first_resolution_time_business,
        tf.request_type,
        tf.client_type,
        tf.step_tag,
        tf.customer_type_tag,
        tf.contact_motivation_tag,
        tf.contact_theme_tag,
        tf.contact_theme_detail_tag,
        tf.ts_created_local AS ts_created,
        tf.ts_updated_local AS ts_updated,
        ftm.ts_solved_local AS ts_solved
    FROM
        datalake_zendesk_ticket_funnels.ticket_funnel tf
    LEFT JOIN
        datalake_zendesk_ticket_funnels.tickets_funnel_metrics ftm
            ON tf.id_ticket = ftm.id_ticket
    LEFT JOIN 
        historical_datalake_zendesk_clean.chats c
            ON c.id_ticket = tf.id_ticket
    LEFT JOIN
        datalake_zendesk_tickets_clean.tickets t
            ON t.id_ticket = tf.id_ticket
    WHERE
        tf.ts_created < "2020-08-20T11:18:44.415+0000"
        AND tf.channel = "chat"
),
chat_engagements AS (
    SELECT
        ce.id,
        ce.id_chat,
        ce.id_department,
        ce.id_agent,
        ce.agent_name,
        ce.comment,
        ce.department_name,
        FIRST(ce.department_name) OVER (PARTITION BY ce.id_chat ORDER BY ce.ts_started_utc ASC) AS first_department,
        FIRST(ce.department_name) OVER (PARTITION BY ce.id_chat ORDER BY ce.ts_started_utc DESC) AS last_department,
        LAG(ce.department_name,1) OVER (PARTITION BY ce.id_chat ORDER BY ce.ts_started_utc) AS transferred_from_dept,
        LEAD(ce.department_name,1) OVER (PARTITION BY ce.id_chat ORDER BY ce.ts_started_utc) AS transferred_to_dept,
        ce.duration AS minutes_talk_time,
        ce.response_time,
        ce.ts_started_utc,
        ce.ts_ended_utc
    FROM 
        historical_datalake_zendesk.chat_engagements ce
    WHERE
        ce.department_name <> "Escolha uma opção"
),
chats_details AS (
    SELECT
        ce.id_chat,
        COUNT(DISTINCT ce.id_department) as number_of_departments,
        COUNT(ce.id) AS number_of_segments,
        SUM(CAST(ce.minutes_talk_time AS DOUBLE))/60.0 AS total_minutes_talk_time,
        MIN(ts_started_utc) AS ts_chat_closed,
        MAX(ts_ended_utc) AS ts_chat_created
    FROM
        chat_engagements ce
    GROUP BY id_chat
)
SELECT DISTINCT
    ce.id AS id_segment,
    zd.id_ticket,
    COALESCE(ce.id_chat, zd.id_ticket) AS id_conversation,
    zd.id_chat,
    zd.id_session,
    COALESCE(ce.id_agent, zd.id_assignee) AS id_agent,
    FIRST(ce.id_agent) OVER (PARTITION BY zd.id_ticket ORDER BY ce.ts_started_utc ASC) AS id_first_agent,
    FIRST(ce.id_agent) OVER (PARTITION BY zd.id_ticket ORDER BY ce.ts_started_utc DESC) AS id_last_agent,
    zd.id_user,
    zd.id_contract,
    ac.email AS agent_email,
    ac.manager AS agent_manager,
    COALESCE(ce.agent_name, ac.agent_name) AS agent_name, 
    ac.agent_company,
    COALESCE(ce.comment, cc.comment) AS csat_comment,
    ce.department_name AS department,
    zd.zendesk_ticket_department AS zendesk_department,
    ce.first_department, 
    ce.last_department,
    ce.transferred_from_dept,
    ce.transferred_to_dept,
    zd.request_type,
    zd.client_type,
    zd.step_tag,
    zd.customer_type_tag,
    zd.contact_motivation_tag,
    zd.contact_theme_tag,
    zd.contact_theme_detail_tag,
    zd.tags,
    zd.status,
    zd.custom_fields,
    FIRST(GET_JSON_OBJECT(ce.response_time,'$.first')) OVER (PARTITION BY zd.id_ticket ORDER BY ce.ts_started_utc ASC) AS seconds_first_reply,
    cd.number_of_departments,
    cd.number_of_segments,  
    COALESCE(zd.minutes_first_resolution_time_calendar, cd.total_minutes_talk_time) AS minutes_first_resolution_time_calendar,
    zd.minutes_first_resolution_time_business,
    cd.total_minutes_talk_time,
    FIRST(ce.id) OVER (PARTITION BY zd.id_chat ORDER BY ce.ts_started_utc DESC) = ce.id AS is_last_segment,
    FIRST(ce.id) OVER (PARTITION BY zd.id_chat ORDER BY ce.ts_started_utc ASC) = ce.id AS is_first_segment,
    zd.tags LIKE '%bot_end_conversation%' AS is_bot,
    zd.tags LIKE '%closed_by_merge%' AS is_closed_by_merge, 
    CASE 
        WHEN dc.front_or_back = 'Front' THEN 'front'
        WHEN dc.front_or_back = 'Back' OR zd.tags LIKE '%tarefa_atendimento_escalado%' THEN 'back'
        ELSE 'undefined'
    END AS front_or_back,
    cc.id_ticket IS NOT NULL AS is_csat_answered,
    cc.is_solved,
    cc.csat_score,
    cc.group_name,
    cc.ts_survey,
    ce.ts_started_utc AS dt_agent_start,
    zd.ts_created,
    zd.ts_updated,
    ce.ts_started_utc AS ts_segment_created,
    ce.ts_ended_utc AS ts_segment_closed,
    cd.ts_chat_created AS ts_ticket_started,
    cd.ts_chat_closed AS ts_ticket_ended
FROM 
    zendesk_aditional_ticket_info zd
LEFT JOIN 
    chat_engagements ce
        ON ce.id_chat = zd.id_chat
LEFT JOIN  
    chat_csat cc
        ON cc.id_ticket = zd.id_ticket
LEFT JOIN 
    datalake_gsheets_clean.agents_control ac
        ON zd.id_assignee = ac.id_assignee
LEFT JOIN
    chats_details cd
        ON cd.id_chat = ce.id_chat
LEFT JOIN
    datalake_gsheets_clean.department_control dc
      ON dc.department = zd.zendesk_ticket_department