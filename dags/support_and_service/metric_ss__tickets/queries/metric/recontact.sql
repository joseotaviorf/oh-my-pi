WITH tickets_perspective AS (
  SELECT DISTINCT
    ft.sk_ticket,
    ft.sk_user,
    CASE
      WHEN ft.channel IN ('chat','call') THEN ft.channel
      WHEN dit.ticket_via = 'whatsapp' THEN 'whatsapp'
      ELSE ft.channel
    END AS channel,
    dt.journey,
    dd_last.journey_step,
    dd_last.board,
    dd_last.department,
    dd_last.team,
    dd_last.area,
    dt.customer_type_tag AS customer_type,
    CASE
      WHEN ft.ticket_origin = 'call inapp' THEN UPPER(dc.direction)
      WHEN ft.ticket_origin = 'call inbound' THEN 'INBOUND'
      WHEN ft.ticket_origin = 'chat5a' THEN 'INBOUND'
      WHEN ft.ticket_origin = 'call outbound' THEN 'OUTBOUND'
      ELSE UPPER(dc.direction)
    END AS refined_direction,
    ft.front_or_back,
    ft.ts_started
  FROM
    dw_customer_support.fact_ticket AS ft
  LEFT JOIN
    dw_customer_support.dim_department AS dd_last
      ON dd_last.sk_department = ft.sk_main_department
  LEFT JOIN
    dw_customer_support.dim_taxonomy AS dt
      ON dt.sk_taxonomy = ft.sk_taxonomy
  LEFT JOIN
    dw_tickets.dim_ticket AS dit
      ON dit.sk_ticket = ft.sk_ticket
  LEFT JOIN
    dw_customer_support.dim_channel AS dc
      ON dc.sk_channel = ft.sk_channel
  WHERE
    ft.ts_started >= CAST('2021-01-01' AS DATE)
)
, recontact_d4 AS (
  SELECT
    sk_ticket,
    LAG(DATE(ts_started)) OVER(PARTITION BY sk_user, team ORDER BY ts_started) AS previous_contact_ts_started,
    CASE
      WHEN DATEDIFF(DATE(ts_started), LAG(DATE(ts_started)) OVER(PARTITION BY sk_user, team ORDER BY ts_started)) <= 3 THEN 1
      ELSE 0
    END AS recontact_flag
  FROM
    tickets_perspective
  WHERE
    refined_direction = 'INBOUND'
    AND channel IN ('call', 'chat')
    AND sk_user IS NOT NULL
    AND area = 'CX'
    AND front_or_back = 'front'
)
SELECT
  tp.channel,
  tp.journey,
  tp.journey_step,
  tp.board,
  tp.department,
  tp.team,
  tp.area,
  tp.customer_type,
  COUNT(DISTINCT
    CASE
      WHEN rc.recontact_flag = 1 THEN rc.sk_ticket END)
  AS amount_recontact,
  NULLIF((COUNT(DISTINCT
    CASE
        WHEN rc.recontact_flag IS NOT NULL THEN rc.sk_ticket
      END) * 1.0000),0)
  AS amount_recontact_responses,
  CAST(
    COUNT(DISTINCT
      CASE
        WHEN rc.recontact_flag = 1 THEN rc.sk_ticket END)
      /NULLIF((COUNT(DISTINCT
        CASE
            WHEN rc.recontact_flag IS NOT NULL THEN rc.sk_ticket
          END) * 1.0000),0)
    AS DECIMAL(10,4))
  AS recontact_rate,
  DATE(tp.ts_started) AS dt_ticket_created
FROM
    tickets_perspective AS tp
  LEFT JOIN recontact_d4 AS rc
    ON tp.sk_ticket = rc.sk_ticket
GROUP BY
  ALL