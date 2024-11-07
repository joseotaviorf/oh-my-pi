WITH front_tickets_list AS (
  SELECT DISTINCT
    ft.sk_ticket,
    LAG(ft.sk_ticket) OVER(PARTITION BY ft.sk_user, dd.team ORDER BY ft.ts_started) AS sk_ticket_previous_contact,
    LEAD(ft.sk_ticket) OVER(PARTITION BY ft.sk_user ORDER BY ft.ts_started) AS sk_ticket_contact_later,
    ft.sk_user,
    ft.sk_main_department,
    ft.sk_taxonomy,
    da.agent_organization,
    da.email,
    dd.team,
    dd.department,
    dd.journey_step,
    dc.channel,
    ft.ticket_origin,
    dt.theme,
    dt.theme_detail,
    ft.csat_score,
    ft.total_minutes_handling_time,
    ft.total_minutes_queue_time,
    ft.total_minutes_talk_time,
    CASE
      WHEN LAG(ft.sk_ticket) OVER(PARTITION BY ft.sk_user, dd.team ORDER BY ft.ts_started) IS NOT NULL THEN 1
      ELSE 0
    END AS recontact_flag,
    LAG(dc.channel) OVER(PARTITION BY ft.sk_user, dd.team ORDER BY ft.ts_started) AS previous_contact_channel,
    LAG(dt.theme) OVER(PARTITION BY ft.sk_user, dd.team ORDER BY ft.ts_started) AS previous_contact_taxonomy,
    LAG(da.email) OVER(PARTITION BY ft.sk_user, dd.team ORDER BY ft.ts_started) AS previous_contact_email,
    LAG(ft.csat_score) OVER(PARTITION BY ft.sk_user, dd.team ORDER BY ft.ts_started) AS previous_contact_csat,
    DATE_DIFF(DATE(ft.ts_started), LAG(DATE(ft.ts_started)) OVER(PARTITION BY ft.sk_user, dd.team ORDER BY ft.ts_started)) AS days_since_last_contact,
    LAG(ft.ts_started) OVER(PARTITION BY ft.sk_user, dd.team ORDER BY ft.ts_started) AS ts_started_previous_contact,
    DATE_SUB(ft.ts_started, 3) AS search_window_from,
    ft.ts_started
  FROM
    dw_customer_support.fact_ticket AS ft
  LEFT JOIN
    dw_customer_support.dim_department AS dd
      ON ft.sk_main_department = dd.sk_department
  LEFT JOIN
    dw_customer_support.dim_channel AS dc
      ON ft.sk_channel = dc.sk_channel
  LEFT JOIN
    dw_customer_support.dim_taxonomy AS dt
      ON ft.sk_taxonomy = dt.sk_taxonomy
  LEFT JOIN
    dw_customer_support.dim_agent as da
      ON ft.sk_last_agent = da.sk_agent
      OR ft.sk_last_agent = da.sk_agent_twilio
  WHERE
    ft.sk_user IS NOT NULL
    AND dd.area = 'CX'
    AND ft.front_or_back = 'front'
    AND ( (dc.channel = 'chat' AND dc.direction = 'inbound')
        OR (ft.ticket_origin IN ('call inbound', 'call inapp')) )
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
    rc.ts_started BETWEEN DATE(rc.ts_started'{load_start_date}') - INTERVAL '45' DAY AND DATE('{load_end_date}')
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
  YEAR(rc.ts_started) AS year,
  MONTH(rc.ts_started) AS month,
  DAY(rc.ts_started) AS day,
  NOW() AS ts_load
FROM
  recontact_check AS rc