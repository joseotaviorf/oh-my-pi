WITH call_tickets AS (
  SELECT DISTINCT
    CAST(id_ticket AS BIGINT) AS sk_ticket,
    MD5(
      CONCAT(
        COALESCE(customer_type_tag, ''),
        COALESCE(client_type, ''),
        COALESCE(request_type, ''),
        COALESCE(contact_motivation_tag, ''),
        COALESCE(contact_theme_tag, '')
      )
    ) AS sk_taxonomy,
    MD5(concat('call', tags, direction)) AS sk_channel,
    MD5(first_department) AS sk_first_department,
    MD5(last_department) AS sk_last_department, 
    id_user AS sk_user,
    id_contract AS sk_contract,
    'call' AS channel,
    csat_rating AS csat_score,
    status,
    minutes_full_resolution_time_calendar,
    first_department,
    last_department,
    number_of_departments AS total_departments,
    number_of_tasks AS total_tasks,
    CAST(back_ticket AS BIGINT) AS back_ticket,
    is_solved AS resolution_survey,
    is_csat_answered AS has_anwsered_survey,
    has_back_ticket,
    is_open_back_ticket AS is_back_ticket_open,
    CASE
      WHEN is_solved = TRUE
          AND (back_ticket IS NULL OR is_open_back_ticket = FALSE)
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
      THEN TRUE
      WHEN is_solved IS NOT NULL 
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
      THEN FALSE
      ELSE NULL
    END AS is_solved,
    CASE
      WHEN is_solved = TRUE
          AND back_ticket IS NULL
          AND has_transfers = FALSE
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
      THEN TRUE
      WHEN is_solved IS NOT NULL
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE 
      THEN FALSE
      ELSE NULL
    END AS is_fcr,
    has_transfers,
    ts_ticket_started AS ts_started,
    ts_ticket_ended AS ts_closed,
    NOW() AS ts_load
  FROM
    datalake_front_tickets.call
),
chat_tickets AS (
  SELECT DISTINCT
    CAST(id_ticket AS BIGINT) AS sk_ticket,
    MD5(
      CONCAT(
        COALESCE(client_type, ''),
        COALESCE(request_type, ''),
        COALESCE(contact_motivation_tag, ''),
        COALESCE(contact_theme_tag, '')
      )
    ) AS sk_taxonomy,
    MD5(concat('chat', tags)) AS sk_channel,
    MD5(first_department) AS sk_first_department,
    MD5(last_department) AS sk_last_department,
    id_user AS sk_user,
    id_contract AS sk_contract, 
    'chat' AS channel,
    csat_score,
    status,
    minutes_full_resolution_time_calendar,
    first_department,
    last_department,
    number_of_departments AS total_departments,
    number_of_tasks AS total_tasks,
    CAST(back_ticket AS BIGINT) AS back_ticket,
    is_solved AS resolution_survey,
    is_csat_answered AS has_anwsered_survey,
    has_back_ticket,
    is_open_back_ticket AS is_back_ticket_open,
    CASE
      WHEN is_solved = TRUE
          AND (back_ticket IS NULL OR is_open_back_ticket = FALSE)
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
      THEN TRUE
      WHEN is_solved IS NOT NULL 
          AND is_bot = FALSE 
          AND is_closed_by_merge = FALSE
      THEN FALSE
      ELSE NULL
    END AS is_solved,
    CASE
      WHEN is_solved = TRUE
          AND back_ticket IS NULL
          AND number_of_departments <= 1
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE
      THEN TRUE
      WHEN is_solved IS NOT NULL
          AND is_bot = FALSE
          AND number_of_departments > 1
          AND is_closed_by_merge = FALSE
      THEN FALSE
      ELSE NULL
    END AS is_fcr,
    has_transfers,
    ts_ticket_started AS ts_started,
    ts_ticket_ended AS ts_closed,
    NOW() AS ts_load
  FROM
    datalake_front_tickets.chat
),
email_tickets AS (
  SELECT DISTINCT
    CAST(id_ticket AS BIGINT) AS sk_ticket,
    MD5(
      CONCAT(
        COALESCE(client_type, ''),
        COALESCE(request_type, ''),
        COALESCE(contact_motivation_tag, ''),
        COALESCE(contact_theme_tag, '')
      )
    ) AS sk_taxonomy,
    MD5(concat('email', tags)) AS sk_channel,
    MD5(department) AS sk_first_department,
    MD5(department) AS sk_last_department, 
    id_user AS sk_user,
    id_contract AS sk_contract,
    'email' AS channel,
    csat_score,
    status,
    minutes_full_resolution_time_calendar,
    department AS first_department,
    department AS last_department,
    1 AS total_departments,
    1 AS total_tasks,
    CAST(back_ticket AS BIGINT) AS back_ticket,
    is_solved AS resolution_survey,
    is_answered AS has_anwsered_survey,
    has_back_ticket,
    is_open_back_ticket AS is_back_ticket_open,
    CASE
      WHEN is_solved = TRUE
          AND (back_ticket IS NULL OR is_open_back_ticket = FALSE)
          AND is_bot = FALSE 
          AND is_closed_by_merge = FALSE
      THEN TRUE
      WHEN is_solved IS NOT NULL 
          AND is_bot = FALSE
          AND is_closed_by_merge = FALSE 
      THEN FALSE
      ELSE NULL
    END AS is_solved,
    CASE
      WHEN is_solved = TRUE
          AND back_ticket IS NULL
          AND is_bot = FALSE 
          AND is_closed_by_merge = FALSE
      THEN TRUE
      WHEN is_solved IS NOT NULL
          AND is_bot = FALSE 
          AND is_closed_by_merge = FALSE
      THEN FALSE
      ELSE NULL
    END AS is_fcr,
    NULL AS has_transfers,
    ts_ticket_started AS ts_started,
    ts_ticket_ended AS ts_closed,
    NOW() AS ts_load
  FROM 
    datalake_front_tickets.email
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