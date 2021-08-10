WITH chat_total AS (
  SELECT
    cc.id_ticket,
    'chat' AS channel,
    SUBSTR(sa.comment,1,1000) AS csat_comment,
    'chat_fup' AS source,
    sa.is_solved AS resolution_survey,
    sa.rating AS csat_score,
    ss.ts_created AS ts_survey,
    sa.ts_created AS ts_response
  FROM
    datalake_zendesk_ticket_funnels.ticket_funnel AS zf
  INNER JOIN
    datalake_chat_fup_clean.chats_chat AS cc
      ON zf.id_ticket = cc.id_ticket
  LEFT JOIN
    datalake_chat_fup_clean.surveys_survey AS ss
      ON cc.id = ss.id_chat
  LEFT JOIN
    datalake_chat_fup_clean.surveys_answer AS sa
      ON ss.id = sa.id_survey
  WHERE
    COALESCE(CAST(sa.is_solved AS string), CAST(sa.rating AS string)) IS NOT NULL
),
email_total AS (
  WITH last_update_ticket AS (
    SELECT
      id_ticket,
      MAX(ts_updated) AS ts_last_updated
    FROM
      datalake_zendesk_tickets_clean.tickets
    GROUP BY 1
  ),
  csat AS (
    SELECT
      t.id_ticket AS id_ticket,
      GET_JSON_OBJECT(satisfaction_rating, '$.comment') AS csat_comment,
      'zendesk' AS source,
      GET_JSON_OBJECT(satisfaction_rating, '$.reason') AS score_reason,
      satisfaction_rating,
      CASE
        WHEN GET_JSON_OBJECT(satisfaction_rating, '$.score') = 'bad' THEN 1
        WHEN GET_JSON_OBJECT(satisfaction_rating, '$.score') = 'good' THEN 5
        ELSE NULL
      END AS csat_score,
      GET_JSON_OBJECT(satisfaction_rating, '$.score') IN ('good', 'bad') AS is_answered,
      CASE
        WHEN GET_JSON_OBJECT(satisfaction_rating, '$.score') IN ('good') THEN TRUE
        WHEN GET_JSON_OBJECT(satisfaction_rating, '$.score') IN ('bad') THEN FALSE
      END AS is_solved,
      NULL AS ts_first_seen,
      MIN(sr.ts_updated) OVER(PARTITION BY t.id_ticket) AS ts_first_response
    FROM
      datalake_zendesk_tickets_clean.tickets t
    JOIN
      last_update_ticket lut
        ON t.id_ticket = lut.id_ticket
        AND t.ts_updated = lut.ts_last_updated
    LEFT JOIN
      datalake_zendesk_tickets_clean.satisfaction_ratings AS sr
        ON sr.id_ticket = lut.id_ticket
    UNION ALL
    SELECT
      id_ticket,
      user_comment AS csat_comment,
      'survicate' AS source,
      NULL AS score_reason,
      NULL AS satisfaction_rating,
      csat_score,
      COALESCE(
        CAST(user_comment AS STRING),
        CAST(csat_score AS STRING),
        CAST(is_solved AS STRING)
      ) IS NOT NULL AS is_answered,
      is_solved,
      ts_first_seen,
      ts_first_response
    FROM
      datalake_survicate.surveys
    WHERE
      id_ticket IS NOT NULL
    GROUP BY 1,2,3,4,5,6,7,8,9,10    
  )
  SELECT
    csat.id_ticket,
    'email' AS channel,
    SUBSTR(csat.csat_comment,1,1000) AS csat_comment,
    source,
    csat.is_solved AS resolution_survey,
    csat.csat_score,
    NULL AS ts_survey,
    csat.ts_first_response AS ts_response
  FROM
    csat
    JOIN
      datalake_zendesk_tickets_clean.tickets AS t
        ON csat.id_ticket = t.id_ticket
    JOIN
      datalake_zendesk_ticket_funnels.ticket_funnel AS tf
        ON tf.id_ticket = t.id_ticket
  WHERE
    tf.channel IN ('email', 'form_faq', 'web', 'other')
    AND COALESCE(CAST(is_solved AS string), CAST(csat_score AS string)) IS NOT NULL
    -- emails with the tags below are not new demands or automatically closed, therefore, they should not be considered
    AND tf.tags NOT LIKE '%resolve_ticket_acompanhamento%'
    AND tf.tags NOT LIKE '%fechado_automaticamente_noreply%'
    AND tf.tags NOT LIKE '%redirecionado_atendimento_2%'
    AND tf.tags NOT LIKE '%closed_by_merge%'
    AND tf.tags NOT LIKE '%zapdesk%'
    AND tf.tags NOT LIKE '%ticket_via_call%'
    AND tf.tags NOT LIKE '%call_contato_receptivo%'
    AND tf.tags NOT LIKE '%call_contato_ativo%'
    AND tf.tags NOT LIKE '%redirecionado_adm_v1%'
  GROUP BY 1,2,3,4,5,6,7,8
),
call_total AS (
  WITH ivr_events AS (
    SELECT
      id_call,
      MAX(ts_created_local) AS ts_last_event
    FROM
      datalake_bigfone_twilio.call_ivr_events
      GROUP BY 1
  ),
  call_events AS (
    SELECT
        id_task,
        id_call,
        id_conversation
    FROM
        datalake_bigfone_twilio.call_flex_events
    WHERE
        event_type != 'task.updated'
        AND (
          GET_JSON_OBJECT(metadata, '$.event_data.TaskAttributes.scheduled') IS NULL
          OR GET_JSON_OBJECT(metadata, '$.event_data.TaskAttributes.scheduled') <> 'true'
          OR (
                GET_JSON_OBJECT(metadata, '$.event_data.TaskAttributes.scheduled') = 'true' 
                AND GET_JSON_OBJECT(metadata, '$.event_data.TaskAttributes.conversations.conversation_attribute_1') = 2
          )
        )
        GROUP BY 1,2,3
  ),
  csat_events AS (
    SELECT
      id_call,
      id_task,
      MAX(csat_1) AS csat_1,
      MAX(csat_2) AS csat_2,
      MIN(ts_created_local) AS ts_survey, -- On calls the survey answer time is almost the same of the survey's sent time, may be with seconds of difference
      MIN(ts_created_local) AS ts_response
    FROM
      datalake_bigfone_twilio.call_ivr_events
    WHERE
      COALESCE(csat_1, csat_2) IS NOT NULL
    GROUP BY 1,2
  ),
  call AS (
    SELECT
      COALESCE(ie.id_call, fe.id_call, fe.id_conversation, fe.id_task) AS sk_call
    FROM
        ivr_events AS ie
    FULL JOIN
        call_events AS fe
            ON fe.id_call = ie.id_call
  ),
  zendesk_tickets_unique AS (
    --this CTE fix the error of multiple tickets openned for a single call
    SELECT
      tfm.id_call,
      MAX(tfm.id_ticket) AS id_ticket
    FROM
      datalake_zendesk_ticket_funnels.tickets_funnel_metrics AS tfm
    WHERE
      id_call IS NOT NULL
    GROUP BY 1
  )
  SELECT
    ztu.id_ticket,
    'call' AS channel,
    NULL AS csat_comment,
    'bigfone' AS source,
    CASE
      WHEN csat_1 = 1 THEN TRUE
      WHEN csat_1 = 2 THEN FALSE
    END AS resolution_survey,
    csat_2 AS csat_score,
    ts_survey,
    ts_response
  FROM
    zendesk_tickets_unique AS ztu
  JOIN
    call AS c
      ON c.sk_call = ztu.id_call
  JOIN
    csat_events AS csat
      ON csat.id_call = ztu.id_call
)
SELECT
  *
FROM
  chat_total
UNION ALL
SELECT
  *
FROM
  email_total
UNION ALL
SELECT
  *
FROM
  call_total