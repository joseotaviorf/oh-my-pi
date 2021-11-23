WITH front_tickets AS (
  SELECT
    id_ticket,
    MIN(id_user) AS id_user,
    last_back_ticket AS back_ticket,
    direction,
    status,
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
    ts_ticket_started,
    ts_ticket_ended
  FROM 
    datalake_customer_support.call 
  WHERE 
    front_or_back = 'front'
    AND id_user > -1
  GROUP BY 1,3,4,5,6,7,8
  UNION ALL 
  SELECT
    id_ticket,
    MIN(id_user) AS id_user,
    last_back_ticket AS back_ticket,
    "inbound" AS direction,
    status,
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
    ts_ticket_started,
    ts_ticket_ended
  FROM 
    datalake_customer_support.chat 
  WHERE 
    front_or_back = 'front'
    AND id_user > -1
  GROUP BY 1,3,4,5,6,7,8
  UNION ALL 
  SELECT
    id_ticket,
    MIN(id_user) AS id_user,
    last_back_ticket AS back_ticket,
    direction,
    status,
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
    ts_ticket_started,
    ts_ticket_ended
  FROM 
    datalake_customer_support.email 
  WHERE 
    front_or_back = 'front'
    AND id_user > -1
  GROUP BY 1,3,4,5,6,7,8
),
user_recontacts AS (
  SELECT DISTINCT 
    id_ticket,
    id_user,
    CASE
      WHEN ((BIGINT(TO_TIMESTAMP(ts_ticket_started)) - BIGINT(TO_TIMESTAMP(LAG(ts_ticket_started, 1) OVER(PARTITION BY id_user ORDER BY ts_ticket_started))))/(3600)) < 168 THEN 1
      ELSE 0
    END AS is_recontact,
    CASE
      WHEN ((BIGINT(TO_TIMESTAMP(ts_ticket_started)) - BIGINT(TO_TIMESTAMP(LAG(ts_ticket_started, 1) OVER(PARTITION BY id_user ORDER BY ts_ticket_started))))/(3600)) < 168 THEN NULL
      ELSE id_ticket
    END AS main_ticket,
    ts_ticket_started
  FROM
    front_tickets 
),
ticket_sessions AS (
  SELECT
    id_ticket,
    MAX(main_ticket) OVER(PARTITION BY id_user ORDER BY ts_ticket_started ASC ROWS UNBOUNDED PRECEDING) AS main_ticket,
    id_user,
    ts_ticket_started
  FROM
    user_recontacts
),
tickets_by_ticket_session AS (
  SELECT
    main_ticket,
    id_user,
    COUNT(DISTINCT id_ticket) AS total_tickets,
    MIN(ts_ticket_started) AS ts_started
  FROM
    ticket_sessions
  GROUP BY 1,2
)
SELECT
    tts.main_ticket AS id_ticket,
    tts.id_user,
    tts.total_tickets,
    CASE
        WHEN tts.total_tickets > 1
            OR ft.back_ticket IS NOT NULL
            OR is_solved = False
        THEN FALSE
        ELSE TRUE
    END AS is_fcr,
    ft.ts_ticket_started,
    ft.ts_ticket_ended
FROM 
    tickets_by_ticket_session AS tts
LEFT JOIN 
    front_tickets AS ft
        ON ft.id_ticket = tts.main_ticket
WHERE
    (direction = 'inbound' OR direction IS NULL)
    AND status = 'closed'