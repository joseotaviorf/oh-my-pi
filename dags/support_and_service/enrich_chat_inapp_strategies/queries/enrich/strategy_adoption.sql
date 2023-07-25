--ADICIONANDO SESSION ORDER - ATRIBUI UMA ORDEM PARA A CRIAÇÃO DE SESSÕES
WITH session_order AS (
  SELECT
    *,
    ROW_NUMBER() OVER(PARTITION BY id_user ORDER BY ts_started ASC) AS session_order
  FROM
    datalake_chat_inapp_strategies.whatsapp_sessions
),
conversion AS (
  SELECT
    *,
    CASE
      WHEN
        migration_strategy_adjusted IN ("suggest","open","last_open")
        AND has_chat5a_access IS TRUE
        AND LEAD(id_pipeline) OVER (PARTITION BY id_user ORDER BY ts_started ASC) = "in_app_main"
        AND LEAD(session_order) OVER (PARTITION BY id_user ORDER BY ts_started ASC) = session_order + 1
      THEN "sim"
      WHEN
        migration_strategy_adjusted = "close"
        AND has_chat5a_access = TRUE
        AND LEAD(id_pipeline) OVER (PARTITION BY id_user ORDER BY ts_started ASC) = "in_app_main"
        AND LEAD(session_order) OVER (PARTITION BY id_user ORDER BY ts_started ASC) = session_order + 1
      THEN "sim"
      WHEN
        has_chat5a_access IS NULL
        AND migration_strategy IS NULL
        AND migration_strategy_adjusted IN ("organic")
        AND id_pipeline = "in_app_main" THEN "sim"
      ELSE NULL
    END AS houve_conversao
  FROM
    session_order
)
SELECT
  tu.id_session,
  tu.id_user,
  tu.id_pipeline,
  atc.id_conversation,
  tu.id_ticket,
  atc.id_segment,
  tu.session_order,
  tu.migration_strategy,
  tu.migration_strategy_adjusted,
  tu.contract_role,
  tu.tag,
  tu.grade_bot,
  tu.comment_bot,
  tu.grade_human,
  tu.comment_human,
  tu.currently_tenant_post,
  atc.ticket_origin,
  atc.completion_reason,
  atc.department,
  atc.seconds_first_reply,
  atc.total_minutes_queue_time,
  atc.total_minutes_talk_time,
  atc.total_minutes_wrap_up_time,
  atc.total_minutes_handling_time,
  tu.has_chat5a_access,
  tu.has_installed_app,
  tu.houve_conversao,
  atc.is_solved,
  tu.is_solved_human,
  tu.is_retention,
  tu.ts_started,
  atc.ts_ticket_started
FROM
  conversion AS tu
LEFT JOIN
  datalake_customer_support.chat atc
    ON tu.id_ticket = atc.id_ticket
