WITH time_metrics AS (
  SELECT DISTINCT
    sk_ticket,
    total_handling_time / 60 AS total_minutes_handling_time,
    total_waiting_time / 60 AS total_minutes_queue_time,
    total_talk_time / 60 AS total_minutes_talk_time
  FROM
    dw_customer_support.fact_customer_contacts
),
front_tickets_list AS (
  SELECT DISTINCT
    ft.sk_ticket,
    LAG(ft.sk_ticket) OVER(PARTITION BY ft.sk_user, dd.team ORDER BY ft.ts_created) AS sk_ticket_previous_contact,
    LEAD(ft.sk_ticket) OVER(PARTITION BY ft.sk_user ORDER BY ft.ts_created) AS sk_ticket_contact_later,
    ft.sk_user,
    ft.sk_main_department,
    ft.sk_taxonomy,
    da.agent_organization,
    da.email,
    dd.team,
    dd.department,
    dd.journey_step,
    ft.channel,
    ft.ticket_origin,
    dt.theme,
    dt.theme_detail,
    ftc.last_csat_score AS csat_score,
    tm.total_minutes_handling_time,
    tm.total_minutes_queue_time,
    tm.total_minutes_talk_time,
    CASE
      WHEN LAG(ft.sk_ticket) OVER(PARTITION BY ft.sk_user, dd.team ORDER BY ft.ts_created) IS NOT NULL THEN 1
      ELSE 0
    END AS recontact_flag,
    LAG(ft.channel) OVER(PARTITION BY ft.sk_user, dd.team ORDER BY ft.ts_created) AS previous_contact_channel,
    LAG(dt.theme) OVER(PARTITION BY ft.sk_user, dd.team ORDER BY ft.ts_created) AS previous_contact_taxonomy,
    LAG(da.email) OVER(PARTITION BY ft.sk_user, dd.team ORDER BY ft.ts_created) AS previous_contact_email,
    LAG(ftc.last_csat_score) OVER(PARTITION BY ft.sk_user, dd.team ORDER BY ft.ts_created) AS previous_contact_csat,
    DATE_DIFF(DATE(ft.ts_created), LAG(DATE(ft.ts_created)) OVER(PARTITION BY ft.sk_user, dd.team ORDER BY ft.ts_created)) AS days_since_last_contact,
    LAG(ft.ts_created) OVER(PARTITION BY ft.sk_user, dd.team ORDER BY ft.ts_created) AS ts_started_previous_contact,
    DATE_SUB(ft.ts_created, 3) AS search_window_from,
    ft.ts_created AS ts_started
  FROM
    dw_customer_support.fact_tickets AS ft
  LEFT JOIN
    dw_satisfaction_rating.fact_ticket_csat AS ftc
      ON ftc.sk_ticket = ft.sk_ticket
  LEFT JOIN
    time_metrics AS tm
      ON tm.sk_ticket = ft.sk_ticket
  LEFT JOIN
    dw_customer_support.dim_department AS dd
      ON ft.sk_main_department = dd.sk_department
  LEFT JOIN
    dw_customer_support.dim_taxonomy AS dt
      ON ft.sk_taxonomy = dt.sk_taxonomy
  LEFT JOIN
    dw_customer_support.dim_analyst AS da
      ON ft.sk_last_analyst = da.sk_analyst
      OR ft.sk_last_analyst = da.sk_agent_twilio
  WHERE
    ft.sk_user IS NOT NULL
    AND dd.area = 'CX'
    AND ft.front_or_back = 'front'
    AND ( (ft.channel = 'chat' AND ft.direction = 'inbound')
        OR (ft.ticket_origin IN ('call inbound', 'call in app')) )
),
tbl_completion_reason AS (
  SELECT
    fs.sk_ticket,
    MAX(CASE WHEN fs.completion_reason = 'task idled' THEN 1 ELSE 0 END) AS flag_last_completion_reason_idled
  FROM
    dw_customer_support.fact_segment AS fs
  WHERE
    fs.is_last_segment = True
  GROUP BY ALL
),
recontact_check AS (
  SELECT
    rc.sk_ticket,
    channel,
    ticket_origin,
    sk_main_department,
    sk_taxonomy,
    sk_user,
    agent_organization,
    team,
    journey_step,
    search_window_from,
    rc.ts_started AS search_window_until,
    days_since_last_contact,
    theme,
    theme_detail,
    CASE
    WHEN rc.days_since_last_contact <= 3 AND rc.team IN ('CX Expert') THEN recontact_flag
    WHEN rc.days_since_last_contact <= 1 AND rc.team IN ('Rental Manager', 'Rental Manager Gold') THEN recontact_flag
    ELSE 0
  END AS recontact_flag,
    sk_ticket_previous_contact,
    ts_started_previous_contact,
    previous_contact_channel,
    COALESCE(flag_last_completion_reason_idled,0) AS flag_last_completion_reason_idled,
    previous_contact_taxonomy,
    csat_score,
    previous_contact_csat,
    total_minutes_handling_time,
    total_minutes_queue_time,
    total_minutes_talk_time,
    email,
    previous_contact_email,
    department,
    sk_ticket_contact_later,
    ts_started
  FROM
    front_tickets_list AS rc
  LEFT JOIN
    tbl_completion_reason
      ON tbl_completion_reason.sk_ticket = rc.sk_ticket_previous_contact
      AND tbl_completion_reason.sk_ticket IS NOT NULL
  WHERE
    rc.ts_started BETWEEN DATE('{load_start_date}') - INTERVAL '45' DAY AND DATE('{load_end_date}')
    AND department NOT LIKE '%[CNX]%'
    AND team IN ('CX Expert', 'Rental Manager', 'Rental Manager Gold')
    AND agent_organization IN ('wh','webhelp','webhelpbr')
)
SELECT
  rc.sk_ticket,
  rc.sk_ticket_previous_contact AS sk_ticket_first_contact,
  rc.sk_ticket_contact_later as sk_ticket_contact_later,
  rc.sk_user,
  rc.channel,
  rc.team,
  rc.email,
  rc.previous_contact_taxonomy AS macrotaxo_first_contact,
  rc.theme as macrotaxo_last_contact,
  rc.theme_detail,
  rc.previous_contact_email AS email_first_contact,
  rc.total_minutes_handling_time,
  rc.total_minutes_queue_time,
  rc.previous_contact_csat AS csat_first_contact,
  rc.csat_score,
  CASE
    WHEN rc.days_since_last_contact <= 0 THEN rc.recontact_flag
    ELSE 0
  END AS recontact_flag,
  rc.search_window_from,
  rc.search_window_until,
  rc.ts_started_previous_contact AS ts_started_first_contact,
  rc.ts_started as ts_started,
  YEAR(CURRENT_DATE - 1) AS year,
  MONTH(CURRENT_DATE - 1) AS month,
  DAY(CURRENT_DATE - 1) AS day,
  NOW() AS ts_load
FROM
  recontact_check AS rc
