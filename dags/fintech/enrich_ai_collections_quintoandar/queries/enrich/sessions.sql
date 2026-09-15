WITH matthew_prod_traces AS (
    SELECT
        t.id_session,
        t.input,
        t.output,
        t.ts_created
    FROM
        datalake_langfuse_clean.traces AS t
    LEFT SEMI JOIN
        datalake_chatbot.sessions AS cs
            ON cs.id_langfuse_session = t.id_session
            AND cs.bot IN ('matthew', 'wall-e')
    WHERE
        t.ts_created >= TIMESTAMP('{load_start_date}') - INTERVAL 2 DAY
        AND t.environment = 'prod'
        AND t.id_session IS NOT NULL
),
trace_first_ranked AS (
    SELECT
        t.id_session AS id_langfuse_session,
        GET_JSON_OBJECT(t.input, '$.user_context.user_last_notifications[0].sent_at') AS notif_ts_extracted,
        GET_JSON_OBJECT(t.input, '$.user_context.user_last_notifications[0].text') AS notif_text_extracted,
        GET_JSON_OBJECT(t.input, '$.user_context.user_last_notifications[0].template') AS notif_template_extracted,
        GET_JSON_OBJECT(t.input, '$.user_context.user_roles') AS user_roles_raw,
        CASE WHEN GET_JSON_OBJECT(t.input, '$.user_context.user_roles') LIKE '%TENANT%' THEN 1 ELSE 0 END AS is_tenant,
        CASE WHEN GET_JSON_OBJECT(t.input, '$.user_context.user_roles') LIKE '%OWNER%' THEN 1 ELSE 0 END AS is_owner,
        CASE
            WHEN GET_JSON_OBJECT(t.input, '$.user_context.user_roles') LIKE '%OWNER%'
                AND GET_JSON_OBJECT(t.input, '$.user_context.user_roles') NOT LIKE '%TENANT%'
                THEN 1
            ELSE 0
        END AS is_owner_only,
        ROW_NUMBER() OVER (PARTITION BY t.id_session ORDER BY t.ts_created ASC) AS rn
    FROM
        matthew_prod_traces AS t
),
trace_first AS (
    SELECT
        id_langfuse_session,
        notif_ts_extracted,
        notif_text_extracted,
        notif_template_extracted,
        user_roles_raw,
        is_tenant,
        is_owner,
        is_owner_only
    FROM
        trace_first_ranked
    WHERE
        rn = 1
),
trace_escalation AS (
    SELECT
        id_session AS id_langfuse_session,
        MAX(
            CASE
                WHEN GET_JSON_OBJECT(output, '$.responses[0].response_type') = 'human_escalation'
                THEN 1
                ELSE 0
            END
        ) AS flag_escalation_attempted,
        MAX(
            CASE
                WHEN GET_JSON_OBJECT(output, '$.responses[0].response_type') = 'human_escalation'
                THEN GET_JSON_OBJECT(
                    output,
                    '$.responses[0].content.hybrid_content.metadata[0].escalation_reason'
                )
                ELSE NULL
            END
        ) AS matthew_declared_escalation_reason,
        MAX(
            CASE
                WHEN GET_JSON_OBJECT(output, '$.responses[0].response_type') = 'human_escalation'
                THEN GET_JSON_OBJECT(
                    output,
                    '$.responses[0].content.hybrid_content.metadata[0].queue_name'
                )
                ELSE NULL
            END
        ) AS matthew_declared_escalation_queue
    FROM
        matthew_prod_traces
    GROUP BY
        id_session
),
score_matthew AS (
    SELECT
        s.id_session AS id_langfuse_session,
        MAX(CASE WHEN s.value > 0 THEN 1 ELSE 0 END) AS flag_score_matthew_in_session
    FROM
        datalake_langfuse_clean.scores AS s
    INNER JOIN
        datalake_chatbot.sessions AS cs
            ON cs.id_langfuse_session = s.id_session
            AND cs.bot IN ('matthew', 'wall-e')
    WHERE
        s.ts_created >= TIMESTAMP('{load_start_date}') - INTERVAL 2 DAY
        AND s.name IN ('SessionContainsMatthewAgentEvaluator', 'MatthewVersionEvaluator')
        AND s.id_session IS NOT NULL
    GROUP BY
        s.id_session
),
sessions_enriched AS (
    SELECT
        m.id_session,
        m.id_sauron_session,
        m.id_sss_session,
        m.id_langfuse_session AS id_external,
        m.id_ticket,
        IF(m.id_user = '', NULL, m.id_user) AS id_user,
        m.bot,
        m.first_queue,
        m.last_queue,
        CASE
            WHEN m.bot = 'matthew' THEN 'Matthew in Whatsapp'
            WHEN m.bot = 'wall-e' AND (
                COALESCE(o.flag_collections_agent_input, 0) = 1
                OR COALESCE(o.flag_debt_retriever_tool, 0) = 1
                OR COALESCE(o.flag_user_debt_classifier_tool, 0) = 1
                OR COALESCE(o.flag_debt_finder_tool, 0) = 1
            ) THEN 'Matthew in Chat'
            ELSE 'Wall-e'
        END AS ai_agent_source,
        CASE
            WHEN m.bot = 'matthew' THEN 'Matthew in Whatsapp'
            WHEN m.bot = 'wall-e' AND COALESCE(sm.flag_score_matthew_in_session, 0) = 1 THEN 'Matthew in Chat'
            ELSE 'Wall-e'
        END AS ai_agent_source_legacy,
        (
            COALESCE(o.flag_collections_agent_input, 0) = 1
            OR COALESCE(o.flag_debt_retriever_tool, 0) = 1
            OR COALESCE(o.flag_user_debt_classifier_tool, 0) = 1
            OR COALESCE(o.flag_debt_finder_tool, 0) = 1
        ) AS is_matthew_in_session,
        CASE
            WHEN m.bot = 'matthew' THEN 1
            WHEN (
                COALESCE(o.flag_collections_agent_input, 0) = 1
                OR COALESCE(o.flag_debt_retriever_tool, 0) = 1
                OR COALESCE(o.flag_user_debt_classifier_tool, 0) = 1
                OR COALESCE(o.flag_debt_finder_tool, 0) = 1
            ) AND (
                COALESCE(o.flag_react_planner_talk_to_user, 0) = 1
                OR COALESCE(o.flag_collectionsinput_talk_to_user, 0) = 1
            ) THEN 1
            ELSE 0
        END AS flag_matthew_talked_to_user,
        CASE
            WHEN o.collections_agent_version IS NOT NULL
                THEN CONCAT('V', CAST(o.collections_agent_version AS STRING))
            WHEN COALESCE(o.flag_collectionsinput_agent, 0) = 1 THEN 'V2'
            WHEN COALESCE(o.flag_debt_retriever_tool, 0) = 1
                OR COALESCE(o.flag_user_debt_classifier_tool, 0) = 1 THEN 'V1.5'
            WHEN COALESCE(o.flag_debt_finder_tool, 0) = 1 THEN 'V1'
            ELSE NULL
        END AS matthew_version,
        CASE
            WHEN m.bot = 'wall-e'
                AND COALESCE(o.flag_collections_agent_input, 0) = 1
            THEN TRUE
            ELSE FALSE
        END AS flag_eval_matthew_in_chat,
        m.is_escalated AS is_escalation,
        COALESCE(te.flag_escalation_attempted, 0) AS flag_escalation_attempted,
        te.matthew_declared_escalation_reason,
        te.matthew_declared_escalation_queue,
        tf.id_langfuse_session IS NOT NULL AS flag_session_with_trace,
        tf.notif_ts_extracted,
        tf.notif_text_extracted,
        tf.notif_template_extracted,
        tf.user_roles_raw,
        tf.is_tenant,
        tf.is_owner,
        tf.is_owner_only,
        DATE(m.ts_created) AS dt_session_created,
        m.ts_created,
        m.ts_updated,
        YEAR(m.ts_updated) AS year,
        MONTH(m.ts_updated) AS month,
        DAYOFMONTH(m.ts_updated) AS day
    FROM
        datalake_chatbot.sessions AS m
    LEFT JOIN
        datalake_ai_collections_quintoandar.observation AS o
            ON o.id_langfuse_session = m.id_langfuse_session
    LEFT JOIN
        trace_first AS tf
            ON tf.id_langfuse_session = m.id_langfuse_session
    LEFT JOIN
        trace_escalation AS te
            ON te.id_langfuse_session = m.id_langfuse_session
    LEFT JOIN
        score_matthew AS sm
            ON sm.id_langfuse_session = m.id_langfuse_session
    WHERE
        m.bot IN ('matthew', 'wall-e')
        AND m.ts_updated >= '{load_start_date}'
),
sessions_deduped AS (
    SELECT
        id_session,
        id_sauron_session,
        id_sss_session,
        id_external,
        id_ticket,
        id_user,
        bot,
        first_queue,
        last_queue,
        ai_agent_source,
        ai_agent_source_legacy,
        is_matthew_in_session,
        flag_matthew_talked_to_user,
        matthew_version,
        flag_eval_matthew_in_chat,
        is_escalation,
        flag_escalation_attempted,
        matthew_declared_escalation_reason,
        matthew_declared_escalation_queue,
        flag_session_with_trace,
        notif_ts_extracted,
        notif_text_extracted,
        notif_template_extracted,
        user_roles_raw,
        is_tenant,
        is_owner,
        is_owner_only,
        dt_session_created,
        ts_created,
        ts_updated,
        year,
        month,
        day,
        ROW_NUMBER() OVER (
            PARTITION BY COALESCE(CAST(id_sss_session AS STRING), CONCAT('id:', CAST(id_session AS STRING)))
            ORDER BY ts_updated DESC NULLS LAST, id_session DESC NULLS LAST
        ) AS rn
    FROM
        sessions_enriched
)
SELECT
    id_session,
    id_sauron_session,
    id_sss_session,
    id_external,
    id_ticket,
    id_user,
    bot,
    first_queue,
    last_queue,
    ai_agent_source,
    ai_agent_source_legacy,
    is_matthew_in_session,
    flag_matthew_talked_to_user,
    matthew_version,
    flag_eval_matthew_in_chat,
    is_escalation,
    flag_escalation_attempted,
    matthew_declared_escalation_reason,
    matthew_declared_escalation_queue,
    flag_session_with_trace,
    notif_ts_extracted,
    notif_text_extracted,
    notif_template_extracted,
    user_roles_raw,
    is_tenant,
    is_owner,
    is_owner_only,
    dt_session_created,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    sessions_deduped
WHERE
    rn = 1
