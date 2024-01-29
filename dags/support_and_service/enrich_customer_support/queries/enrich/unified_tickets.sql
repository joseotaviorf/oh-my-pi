WITH call_tickets AS (
  SELECT
    CAST(id_ticket AS BIGINT) AS id_ticket,
    MD5(
      CONCAT(
        COALESCE(step_tag, ''),
        COALESCE(customer_type_tag, ''),
        COALESCE(client_type, ''),
        COALESCE(request_type, ''),
        COALESCE(contact_motivation_tag, ''),
        COALESCE(contact_theme_tag, ''),
        COALESCE(contact_theme_detail_tag, '')
      )
    ) AS id_taxonomy,
    MD5(tags) AS id_tags,
    MD5(CONCAT('call', 'twilio', COALESCE(direction, ''))) AS id_channel,
    MD5(first_agent_email) AS id_first_agent,
    MD5(last_agent_email) AS id_last_agent,
    MD5(first_department) AS id_first_department,
    MD5(last_department) AS id_main_department,
    MAX(id_user) AS id_user,
    id_contract AS id_contract,
    id_session AS id_session,
    MD5("N/A") AS id_service_status,
    'call' AS channel,
    ticket_origin,
    last_csat_score AS csat_score,
    first_csat_score,
    status,
    first_department,
    last_department AS main_department,
    number_of_departments AS total_departments,
    number_of_segments AS total_segments,
    frt AS full_resolution_time,
    front_or_back,
    CAST(last_back_ticket AS BIGINT) AS last_back_ticket,
    back_ticket_list AS back_tickets,
    is_solved AS resolution_survey,
    IF(
      front_or_back = 'front'
      AND DATE(ts_ticket_ended) >= DATE('2022-01-01')
      AND journey_step NOT IN ('Compra e Venda', 'Cross')
      AND team <> 'Ong Back'
      AND area = 'CX'
      AND last_department NOT IN ('Rescisão por Inadimplência [OFF][POS][BACK]',
        'Offboarding Reparos [OFF] [POS] [BACK]',
        'Offboarding pré saída [OFF] [POS] [BACK]',
        'Proteção QuintoAndar [OFF] [POS] [BACK]',
        'Rescisão - Despejo [OFF][POS][BACK]',
        'Rescisão 1 [OFF] [POS] [BACK]'
      )
      AND (
        direction IN ('inbound', 'outbound-api')
        OR channel_type = 'call-in-app'
      ),
      TRUE,
      FALSE
    ) AS is_ticket_rate,
    is_csat_answered AS has_answered_csat,
    has_back_ticket,
    is_open_back_ticket AS is_back_ticket_open,
    CASE
      WHEN is_solved = TRUE
          AND (back_ticket_list IS NULL OR is_open_back_ticket = FALSE)
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
          AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN TRUE
      WHEN is_solved IS NOT NULL
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
          AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN FALSE
      ELSE NULL
    END AS is_solved,
    CASE
      WHEN is_solved = TRUE
          AND back_ticket_list IS NULL
          AND has_transfers = FALSE
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
          AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN TRUE
      WHEN is_solved IS NOT NULL
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
          AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN FALSE
      ELSE NULL
    END AS is_fcr,
    has_transfers,
    total_minutes_reception_time,
    total_minutes_talk_time,
    total_minutes_queue_time,
    total_minutes_wrap_up_time,
    total_minutes_handling_time,
    total_backoffice_minutes_time,
    total_minutes_front_to_open_back_ticket_time,
    replies,
    reopens,
    NULL AS csat_comment,
    NULL AS first_csat_comment,
    ts_ticket_started AS ts_started,
    ts_ticket_ended AS ts_closed,
    ts_ticket_ended AS ts_solved,
    ts_csat_last_response AS ts_csat_response,
    ts_csat_first_response,
    ts_csat_last_response AS ts_survey
  FROM
    datalake_customer_support.call
  GROUP BY 1,2,3,4,5,6,7,8,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49
),
chat_tickets AS (
  SELECT
    CAST(id_ticket AS BIGINT) AS id_ticket,
    MD5(
      CONCAT(
        COALESCE(step_tag, ''),
        COALESCE(customer_type_tag, ''),
        COALESCE(client_type, ''),
        COALESCE(request_type, ''),
        COALESCE(contact_motivation_tag, ''),
        COALESCE(contact_theme_tag, ''),
        COALESCE(contact_theme_detail_tag, '')
      )
    ) AS id_taxonomy,
    MD5(tags) AS id_tags,
    MD5(CONCAT('chat', 'twilio')) AS id_channel,
    MD5(first_agent_email) AS id_first_agent,
    MD5(last_agent_email) AS id_last_agent,
    MD5(first_department) AS id_first_department,
    MD5(last_department) AS id_main_department,
    MAX(id_user) AS id_user,
    id_contract AS id_contract,
    id_session AS id_session,
    MD5(service_status) AS id_service_status,
    'chat' AS channel,
    ticket_origin,
    last_csat_score AS csat_score,
    first_csat_score,
    status,
    first_department,
    last_department AS main_department,
    number_of_departments AS total_departments,
    number_of_segments AS total_segments,
    frt AS full_resolution_time,
    front_or_back,
    CAST(last_back_ticket AS BIGINT) AS last_back_ticket,
    back_ticket_list AS back_tickets,
    is_solved AS resolution_survey,
    IF(
      front_or_back = 'front'
      AND DATE(ts_ticket_ended) >= DATE('2022-01-01')
      AND journey_step NOT IN ('Compra e Venda', 'Cross')
      AND team <> 'Ong Back'
      AND area = 'CX'
      AND last_department NOT IN ('Rescisão por Inadimplência [OFF][POS][BACK]',
        'Offboarding Reparos [OFF] [POS] [BACK]',
        'Offboarding pré saída [OFF] [POS] [BACK]',
        'Proteção QuintoAndar [OFF] [POS] [BACK]',
        'Rescisão - Despejo [OFF][POS][BACK]',
        'Rescisão 1 [OFF] [POS] [BACK]'
      ),
      TRUE,
      FALSE
    ) AS is_ticket_rate,
    is_csat_answered AS has_answered_csat,
    has_back_ticket,
    is_open_back_ticket AS is_back_ticket_open,
    CASE
      WHEN is_solved = TRUE
          AND (back_ticket_list IS NULL OR is_open_back_ticket = FALSE)
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
          AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN TRUE
      WHEN is_solved IS NOT NULL
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
          AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN FALSE
      ELSE NULL
    END AS is_solved,
    CASE
      WHEN is_solved = TRUE
          AND back_ticket_list IS NULL
          AND number_of_departments <= 1
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
          AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN TRUE
      WHEN is_solved IS NOT NULL
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
          AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN FALSE
      ELSE NULL
    END AS is_fcr,
    has_transfers,
    total_minutes_reception_time,
    total_minutes_talk_time,
    total_minutes_queue_time,
    total_minutes_wrap_up_time,
    total_minutes_handling_time,
    total_backoffice_minutes_time,
    total_minutes_front_to_open_back_ticket_time,
    replies,
    reopens,
    last_csat_comment AS csat_comment,
    first_csat_comment,
    ts_ticket_started AS ts_started,
    ts_ticket_ended AS ts_closed,
    ts_ticket_ended AS ts_solved,
    ts_csat_last_response AS ts_csat_response,
    ts_csat_first_response,
    ts_csat_last_response AS ts_survey
  FROM
    datalake_customer_support.chat
  GROUP BY 1,2,3,4,5,6,7,8,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49
),
email_tickets AS (
  SELECT
    CAST(id_ticket AS BIGINT) AS id_ticket,
    MD5(
      CONCAT(
        COALESCE(step_tag, ''),
        COALESCE(customer_type_tag, ''),
        COALESCE(client_type, ''),
        COALESCE(request_type, ''),
        COALESCE(contact_motivation_tag, ''),
        COALESCE(contact_theme_tag, ''),
        COALESCE(contact_theme_detail_tag, '')
      )
    ) AS id_taxonomy,
    MD5(tags) AS sk_tags,
    MD5(CONCAT('email', 'zendesk', COALESCE(direction, ''))) AS id_channel,
    MD5(agent_email) AS id_first_agent,
    MD5(agent_email) AS id_last_agent,
    MD5(department) AS id_first_department,
    MD5(department) AS id_main_department,
    MAX(id_user) AS id_user,
    id_contract AS id_contract,
    -1 AS id_session,
    MD5("N/A") AS id_service_status,
    'email' AS channel,
    'N/A' AS ticket_origin,
    csat_score,
    first_csat_score,
    status,
    department AS first_department,
    department AS main_department,
    1 AS total_departments,
    1 AS total_segments,
    frt AS full_resolution_time,
    front_or_back,
    CAST(last_back_ticket AS BIGINT) AS last_back_ticket,
    back_ticket_list AS back_tickets,
    is_solved AS resolution_survey,
    IF(
      front_or_back IN ('back', 'front')
      AND DATE(ts_ticket_solved) >= DATE('2022-01-01')
      AND journey_step NOT IN ('Compra e Venda', 'Cross')
      AND team <> 'Ong Back'
      AND area = 'CX'
      AND department NOT IN ('Rescisão por Inadimplência [OFF][POS][BACK]',
        'Offboarding Reparos [OFF] [POS] [BACK]',
        'Offboarding pré saída [OFF] [POS] [BACK]',
        'Proteção QuintoAndar [OFF] [POS] [BACK]',
        'Rescisão - Despejo [OFF][POS][BACK]',
        'Rescisão 1 [OFF] [POS] [BACK]'
      ),
      TRUE,
      FALSE
    ) AS is_ticket_rate,
    is_answered AS has_answered_csat,
    has_back_ticket,
    is_open_back_ticket AS is_back_ticket_open,
    CASE
      WHEN is_solved = TRUE
          AND (back_ticket_list IS NULL OR is_open_back_ticket = FALSE)
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
          AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN TRUE
      WHEN is_solved IS NOT NULL
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
          AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN FALSE
      ELSE NULL
    END AS is_solved,
    CASE
      WHEN is_solved = TRUE
          AND back_ticket_list IS NULL
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
          AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN TRUE
      WHEN is_solved IS NOT NULL
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
          AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN FALSE
      ELSE NULL
    END AS is_fcr,
    NULL AS has_transfers,
    NULL AS total_minutes_reception_time,
    NULL AS total_minutes_talk_time,
    NULL AS total_minutes_queue_time,
    NULL AS total_minutes_wrap_up_time,
    NULL AS total_minutes_handling_time,
    total_backoffice_minutes_time,
    total_minutes_front_to_open_back_ticket_time,
    replies,
    reopens,
    csat_comment,
    first_csat_comment,
    ts_ticket_started AS ts_started,
    ts_ticket_ended AS ts_closed,
    ts_ticket_solved AS ts_solved,
    ts_csat_last_response AS ts_csat_response,
    ts_csat_first_response,
    NULL AS ts_survey
  FROM
    datalake_customer_support.email
  GROUP BY 1,2,3,4,5,6,7,8,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49
),
historical_call_tickets AS (
  SELECT
    CAST(id_ticket AS BIGINT) AS id_ticket,
    MD5(
      CONCAT(
        COALESCE(step_tag, ''),
        COALESCE(customer_type_tag, ''),
        COALESCE(client_type, ''),
        COALESCE(request_type, ''),
        COALESCE(contact_motivation_tag, ''),
        COALESCE(contact_theme_tag, ''),
        COALESCE(contact_theme_detail_tag, '')
      )
    ) AS id_taxonomy,
    NULL AS id_tags,
    MD5(CONCAT('call', 'teravoz', COALESCE(direction, ''))) AS id_channel,
    NULL AS id_first_agent,
    NULL AS id_last_agent,
    MD5(first_department) AS id_first_department,
    MD5(last_department) AS id_main_department,
    MAX(id_user) AS id_user,
    id_contract AS id_contract,
    -1 AS id_session,
    MD5("N/A") AS id_service_status,
    'call' AS channel,
    'N/A' AS ticket_origin,
    NULL AS csat_score,
    NULL AS first_csat_score,
    status,
    first_department,
    last_department AS main_department,
    NULL AS total_departments,
    NULL AS total_segments,
    NULL AS full_resolution_time,
    front_or_back,
    NULL AS last_back_ticket,
    NULL AS back_tickets,
    NULL AS resolution_survey,
    NULL AS is_ticket_rate,
    NULL AS has_answered_csat,
    NULL AS has_back_ticket,
    NULL AS is_back_ticket_open,
    NULL AS is_solved,
    NULL AS is_fcr,
    NULL AS has_transfers,
    NULL AS total_minutes_reception_time,
    total_minutes_talk_time,
    NULL AS total_minutes_queue_time,
    NULL AS total_minutes_wrap_up_time,
    NULL AS total_minutes_handling_time,
    NULL AS total_backoffice_minutes_time,
    NULL AS total_minutes_front_to_open_back_ticket_time,
    NULL AS replies,
    NULL AS reopens,
    NULL AS csat_comment,
    NULL AS first_csat_comment,
    ts_ticket_started AS ts_started,
    ts_ticket_ended AS ts_closed,
    ts_ticket_ended AS ts_solved,
    NULL AS ts_csat_response,
    NULL AS ts_csat_first_response,
    NULL AS ts_survey
  FROM
    datalake_customer_support.historical_call
  GROUP BY 1,2,3,4,5,6,7,8,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49
),
historical_chat_tickets AS (
  SELECT
    CAST(id_ticket AS BIGINT) AS id_ticket,
    MD5(
    CONCAT(
      COALESCE(step_tag, ''),
      COALESCE(customer_type_tag, ''),
      COALESCE(client_type, ''),
      COALESCE(request_type, ''),
      COALESCE(contact_motivation_tag, ''),
      COALESCE(contact_theme_tag, ''),
      COALESCE(contact_theme_detail_tag, '')
    )
    ) AS id_taxonomy,
    NULL AS id_tags,
    MD5(CONCAT('chat', 'zendesk_chat')) AS id_channel,
    id_first_agent AS id_first_agent,
    id_last_agent AS id_last_agent,
    MD5(first_department) AS id_first_department,
    MD5(last_department) AS id_main_department,
    MAX(id_user) AS id_user,
    id_contract AS id_contract,
    -1 AS id_session,
    MD5("N/A") AS id_service_status,
    'chat' AS channel,
    'N/A' AS ticket_origin,
    csat_score,
    NULL AS first_csat_score,
    status,
    first_department,
    last_department AS main_department,
    number_of_departments AS total_departments,
    number_of_segments AS total_segments,
    NULL AS full_resolution_time,
    front_or_back,
    NULL AS last_back_ticket,
    NULL AS back_tickets,
    is_solved AS resolution_survey,
    NULL AS is_ticket_rate,
    is_csat_answered AS has_answered_csat,
    NULL AS has_back_ticket,
    NULL AS is_back_ticket_open,
    CASE
      WHEN is_solved = TRUE
        AND is_bot = FALSE
        AND is_closed_by_merge = FALSE
        AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN TRUE
      WHEN is_solved IS NOT NULL
        AND is_bot = FALSE
        AND is_closed_by_merge = FALSE
        AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN FALSE
      ELSE NULL
    END AS is_solved,
    CASE
      WHEN is_solved = TRUE
        AND number_of_departments <= 1
        AND is_bot = FALSE
        AND is_closed_by_merge = FALSE
        AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN TRUE
      WHEN is_solved IS NOT NULL
        AND is_bot = FALSE
        AND is_closed_by_merge = FALSE
        AND (front_or_back = 'front' OR front_or_back IS NULL)
      THEN FALSE
      ELSE NULL
    END AS is_fcr,
    NULL AS has_transfers,
    NULL AS total_minutes_reception_time,
    total_minutes_talk_time,
    NULL AS total_minutes_queue_time,
    NULL AS total_minutes_wrap_up_time,
    NULL AS total_minutes_handling_time,
    NULL AS total_backoffice_minutes_time,
    NULL AS total_minutes_front_to_open_back_ticket_time,
    NULL AS replies,
    NULL AS reopens,
    NULL AS csat_comment,
    NULL AS first_csat_comment,
    ts_ticket_started AS ts_started,
    ts_ticket_ended AS ts_closed,
    ts_ticket_ended AS ts_solved,
    NULL AS ts_csat_response,
    NULL AS ts_csat_first_response,
    NULL AS ts_survey
  FROM
    datalake_customer_support.historical_chat
  GROUP BY 1,2,3,4,5,6,7,8,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49
),
base_tickets AS (
  SELECT
    *
  FROM
    call_tickets
  UNION ALL
  SELECT
    *
  FROM
    email_tickets
  UNION ALL
  SELECT
    *
  FROM
    chat_tickets
  UNION ALL
  SELECT
    *
  FROM
    historical_call_tickets
  UNION ALL
  SELECT
    *
  FROM
    historical_chat_tickets
)
SELECT DISTINCT
    bt.id_ticket,
    bt.id_taxonomy,
    bt.id_tags,
    bt.id_channel,
    bt.id_first_agent,
    bt.id_last_agent,
    bt.id_first_department,
    bt.id_main_department,
    bt.id_user,
    bt.id_contract,
    bt.id_session,
    bt.id_service_status,
    bt.channel,
    bt.ticket_origin,
    bt.csat_score,
    bt.first_csat_score,
    bt.status,
    bt.first_department,
    bt.main_department,
    bt.total_departments,
    bt.total_segments,
    bt.full_resolution_time,
    bt.front_or_back,
    bt.last_back_ticket,
    bt.back_tickets,
    bt.resolution_survey,
    CASE
      WHEN bt.is_ticket_rate AND bt.front_or_back = 'front' THEN 1
      WHEN bt.is_ticket_rate AND bt.front_or_back = 'back' THEN 2
      ELSE NULL
    END AS ticket_rate_weight,
    bt.is_ticket_rate,
    bt.has_answered_csat,
    bt.has_back_ticket,
    bt.is_back_ticket_open,
    bt.is_solved,
    bt.is_fcr,
    --IF(bt.sk_ticket = fc.sk_main_session, TRUE, FALSE) AS is_ticket_session,
    --IF(bt.sk_ticket = fc.sk_main_session, fc.is_fcr_customer, FALSE) AS is_fcr_customer,
    --CASE
    --  WHEN bt.sk_ticket <> fc.sk_main_session
    --  THEN TRUE
    --  WHEN bt.sk_ticket = fc.sk_main_session
    --  THEN FALSE
    --END AS is_recontact,
    bt.has_transfers,
    bt.total_minutes_reception_time,
    bt.total_minutes_talk_time,
    bt.total_minutes_queue_time,
    bt.total_minutes_wrap_up_time,
    bt.total_minutes_handling_time,
    bt.total_backoffice_minutes_time,
    bt.total_minutes_front_to_open_back_ticket_time,
    bt.replies,
    bt.reopens,
    SUBSTR(bt.csat_comment, 1, 1000) AS csat_comment,
    SUBSTR(bt.first_csat_comment, 1, 1000) AS first_csat_comment,
    bt.ts_started,
    bt.ts_closed,
    bt.ts_solved,
    bt.ts_csat_response,
    bt.ts_csat_first_response,
    bt.ts_survey
FROM
    base_tickets AS bt