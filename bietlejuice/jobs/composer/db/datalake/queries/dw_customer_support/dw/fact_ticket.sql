WITH call_tickets AS (
  SELECT
    CAST(id_ticket AS BIGINT) AS sk_ticket,
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
    ) AS sk_taxonomy,
    MD5(CONCAT('call', 'twilio', COALESCE(direction, ''))) AS sk_channel,
    id_first_agent AS sk_first_agent,
    id_last_agent AS sk_last_agent,
    MD5(first_department) AS sk_first_department,
    MD5(last_department) AS sk_main_department,
    MAX(id_user) AS sk_user,
    id_contract AS sk_contract,
    'call' AS channel,
    csat_rating AS csat_score,
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
    ts_ticket_started AS ts_started,
    ts_ticket_ended AS ts_closed,
    NOW() AS ts_load
  FROM
    datalake_customer_support.call
  GROUP BY 1,2,3,4,5,6,7,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37
),
chat_tickets AS (
  SELECT
    CAST(id_ticket AS BIGINT) AS sk_ticket,
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
    ) AS sk_taxonomy,
    MD5(CONCAT('chat', 'twilio')) AS sk_channel,
    id_first_agent AS sk_first_agent,
    id_last_agent AS sk_last_agent,
    MD5(first_department) AS sk_first_department,
    MD5(last_department) AS sk_main_department,
    MAX(id_user) AS sk_user,
    id_contract AS sk_contract, 
    'chat' AS channel,
    csat_score,
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
    ts_ticket_started AS ts_started,
    ts_ticket_ended AS ts_closed,
    NOW() AS ts_load
  FROM
    datalake_customer_support.chat
  GROUP BY 1,2,3,4,5,6,7,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37
),
email_tickets AS (
  SELECT
    CAST(id_ticket AS BIGINT) AS sk_ticket,
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
    ) AS sk_taxonomy,
    MD5(CONCAT('email', 'zendesk', COALESCE(direction, ''))) AS sk_channel,
    id_agent AS sk_first_agent,
    id_agent AS sk_last_agent,
    MD5(department) AS sk_first_department,
    MD5(department) AS sk_main_department,
    MAX(id_user) AS sk_user,
    id_contract AS sk_contract,
    'email' AS channel,
    csat_score,
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
    ts_ticket_started AS ts_started,
    ts_ticket_ended AS ts_closed,
    NOW() AS ts_load
  FROM 
    datalake_customer_support.email
  GROUP BY 1,2,3,4,5,6,7,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37
),
historical_call_tickets AS (
  SELECT
    CAST(id_ticket AS BIGINT) AS sk_ticket,
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
    ) AS sk_taxonomy,
    MD5(CONCAT('call', 'teravoz', COALESCE(direction, ''))) AS sk_channel,
    NULL AS sk_first_agent,
    NULL AS sk_last_agent,
    MD5(first_department) AS sk_first_department,
    MD5(last_department) AS sk_main_department,
    MAX(id_user) AS sk_user,
    id_contract AS sk_contract,
    'call' AS channel,
    NULL AS csat_score,
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
    ts_ticket_started AS ts_started,
    ts_ticket_ended AS ts_closed,
    NOW() AS ts_load
  FROM
    datalake_customer_support.historical_call
  GROUP BY 1,2,3,4,5,6,7,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37
),
historical_chat_tickets AS (
  SELECT
    CAST(id_ticket AS BIGINT) AS sk_ticket,
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
    ) AS sk_taxonomy,
    MD5(CONCAT('chat', 'zendesk_chat')) AS sk_channel,
    id_first_agent AS sk_first_agent,
    id_last_agent AS sk_last_agent,
    MD5(first_department) AS sk_first_department,
    MD5(last_department) AS sk_main_department,
    MAX(id_user) AS sk_user,
    id_contract AS sk_contract, 
    'chat' AS channel,
    csat_score,
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
    ts_ticket_started AS ts_started,
    ts_ticket_ended AS ts_closed,
    NOW() AS ts_load
  FROM
    datalake_customer_support.historical_chat
  GROUP BY 1,2,3,4,5,6,7,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37
)
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