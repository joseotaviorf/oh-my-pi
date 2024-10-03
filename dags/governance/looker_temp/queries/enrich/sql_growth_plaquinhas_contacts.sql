WITH pre_chatbot_sessions AS (
  SELECT
    id_session,
    DATE(ts_started) AS dt_session_started,
    id_pipeline,
    memory,
    ROW_NUMBER() OVER (PARTITION BY id_session ORDER BY ts_updated DESC) AS rn
  FROM datalake_greenseer_clean.session AS pre_s
  WHERE
    id_pipeline = 'whatsapp_direct_transfer'
    AND GET_JSON_OBJECT(memory, '$.basic.session.department_key') = 'rent_board_test'
    AND pre_s.ts_started <= CURRENT_DATE - INTERVAL '3' DAY
), pos_chatbot_sessions AS (
  SELECT
    DATE(ts_started) AS dt_session_started,
    id_pipeline,
    id_session,
    id_user
  FROM datalake_greenseer.sessions AS pos_s
  WHERE
    pos_s.ts_started >= DATE('2023-03-20') /* data de inicio do bot de plaquinhas */
    AND pos_s.ts_started <= CURRENT_DATE - INTERVAL '3' DAY
    AND pos_s.id_pipeline IN ('whatsapp_real_state_signs', 'whatsapp_real_estate_signs')
), plaquinhas_sessions AS (
  SELECT
    DATE(sessions.ts_started) AS dt_session_started,
    sessions.id_pipeline,
    sessions.id_session,
    sessions.id_user
  FROM datalake_greenseer.sessions
  INNER JOIN pre_chatbot_sessions
    ON pre_chatbot_sessions.id_session = sessions.id_session
    AND pre_chatbot_sessions.rn = 1
  UNION ALL
  SELECT
    dt_session_started,
    id_pipeline,
    id_session,
    NULL AS id_user
  FROM pos_chatbot_sessions
), total_chat AS (
  SELECT DISTINCT
    dt_session_started AS dt_contact,
    'chat' AS contact_channel,
    CAST(id_session AS STRING) AS contact,
    CAST(id_user AS BIGINT) AS id_user
  FROM plaquinhas_sessions
), phone AS (
  SELECT
    dd.date AS dt_contact,
    'phone' AS contact_channel,
    fc.sk_call AS contact,
    CAST(fc.sk_user AS BIGINT) AS id_user
  FROM dw_call.fact_calls AS fc
  INNER JOIN dw_call.dim_call AS dc
    ON fc.sk_call = dc.sk_call AND to_phone_number LIKE '%40202507%'
  INNER JOIN dw_public.dim_date AS dd
    ON fc.sk_call_date = dd.sk_date
)
SELECT
  contact AS id_contact,
  id_user,
  contact_channel,
  dt_contact
FROM phone
UNION ALL
SELECT
  contact AS id_contact,
  id_user,
  contact_channel,
  dt_contact
FROM total_chat