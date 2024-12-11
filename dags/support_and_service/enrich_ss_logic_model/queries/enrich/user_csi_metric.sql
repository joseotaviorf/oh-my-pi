WITH base_tickets AS (
  SELECT
    id_ticket,
    id_user_main AS id_user,
    MD5(last_queue) AS id_main_department,
    'email' AS channel,
    ts_created AS ts_started,
    ts_solved AS ts_solved
  FROM
    datalake_customer_support.tickets
  WHERE
    id_user_main IS NOT NULL
    AND DATE(ts_created) <= DATE('{year}-{month}-{day}')
    AND (
      DATE(ts_solved) <= DATE('{year}-{month}-{day}')
      OR DATE(ts_solved) IS NULL
    )
    AND channel = 'cs email'
),
csi_tickets AS (
  SELECT
    bt.id_ticket,
    bt.id_user,
    bt.channel,
    dc.department,
    NULLIF(dc.journey_step, '-') AS journey_step,
    NULLIF(dc.team, '-') AS team,
    bt.ts_started,
    bt.ts_solved,
    ROW_NUMBER() OVER(PARTITION BY bt.id_user ORDER BY bt.ts_started DESC) AS order_ticket
  FROM
    base_tickets AS bt
  LEFT JOIN
    datalake_gsheets_clean.department_control AS dc
      ON MD5(dc.department) = bt.id_main_department
  WHERE
    dc.department LIKE '%Midias Ops [POS] [BACK]%'
      OR dc.department LIKE '%[CE]%'
)
SELECT
  DATE_FORMAT(DATE('{year}-{month}-{day}'), 'yyyyMMdd') AS id_snapshot,
  ct.id_user,
  MAX(
    CASE
      WHEN ct.order_ticket = 1 THEN ct.id_ticket
      ELSE NULL
    END
  ) AS id_last_csi_ticket,
  COUNT(DISTINCT ct.id_ticket) AS total_csi_tickets_created,
  MAX(
    CASE
      WHEN ct.order_ticket = 1 THEN ct.ts_started
      ELSE NULL
    END
  ) AS ts_most_recent_csi_ticket_creation_date,
  MAX(
    CASE
      WHEN ct.order_ticket = 1 THEN ct.ts_solved
      ELSE NULL
    END
  ) AS ts_most_recent_csi_ticket_solved_date,
  {year} AS year,
  {month} AS month,
  {day} AS day
FROM
  csi_tickets AS ct
GROUP BY 1, 2
