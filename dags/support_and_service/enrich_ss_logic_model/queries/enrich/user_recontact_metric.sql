WITH base_recontact AS (
  SELECT
  id_ticket,
  MAX(id_user_main) AS id_user,
  MD5(last_queue) AS id_main_department,
  last_queue AS main_department,
  contact_theme_tag AS theme,
  contact_theme_detail_tag AS theme_detail,
  channel,
  ts_created AS ts_ticket_started
FROM
  datalake_customer_support.tickets
WHERE
  front_or_back = 'front'
  AND id_user_main IS NOT NULL
  AND channel IN ('call', 'chat')
  AND DATE(ts_created) <= DATE('{year}-{month}-{day}')
GROUP BY ALL
),
base_tickets AS (
  SELECT DISTINCT
    br.id_ticket,
    br.id_main_department,
    br.id_user,
    br.main_department,
    br.theme,
    br.theme_detail,
    NULLIF(dc.team, '-') AS team,
    br.channel,
    br.ts_ticket_started
  FROM
    base_recontact AS br
  LEFT JOIN
    datalake_gsheets_clean.department_control AS dc
      ON MD5(dc.department) = br.id_main_department
  WHERE
    dc.area = 'CX'
),
recontact_check_diff AS (
  SELECT
    bt.id_ticket,
    bt.id_user,
    bt.team,
    bt.channel,
    bt.main_department,
    bt.theme,
    bt.theme_detail,
    bt.ts_ticket_started,
    ROW_NUMBER() OVER(PARTITION BY bt.id_user ORDER BY bt.ts_ticket_started DESC) AS order_ticket,
    LAG(bt.id_ticket) OVER(
      PARTITION BY bt.id_user, bt.team
      ORDER BY bt.ts_ticket_started
    ) AS previous_id_ticket,
    LAG(bt.ts_ticket_started) OVER(
      PARTITION BY bt.id_user, bt.team
      ORDER BY bt.ts_ticket_started
    ) AS previous_ts_started,
    DATEDIFF(
      bt.ts_ticket_started,
      LAG(bt.ts_ticket_started) OVER(
        PARTITION BY bt.id_user, bt.team
        ORDER BY bt.ts_ticket_started
        )
    ) AS time_diff
  FROM
    base_tickets AS bt
)
SELECT
  DATE_FORMAT(DATE('{year}-{month}-{day}'), 'yyyyMMdd') AS id_snapshot,
  rcd.id_user,
  MAX(
    CASE
      WHEN rcd.order_ticket = 1 THEN rcd.id_ticket
      ELSE NULL
    END
  ) AS id_last_created_ticket,
  MAX(
    CASE
      WHEN rcd.order_ticket = 1 THEN rcd.main_department
      ELSE NULL
    END
  ) AS last_ticket_department,
  MAX(
    CASE
      WHEN rcd.order_ticket = 1 THEN rcd.theme
      ELSE NULL
    END
  ) AS last_ticket_theme,
  MAX(
    CASE
      WHEN rcd.order_ticket = 1 THEN rcd.theme_detail
      ELSE NULL
    END
  ) AS last_ticket_theme_detail,
  MAX(
    CASE
      WHEN rcd.order_ticket = 1 THEN rcd.channel
      ELSE NULL
    END
  ) AS last_ticket_channel,
  COUNT(
    DISTINCT
      CASE
        WHEN rcd.ts_ticket_started >= DATE_ADD(DATE('{year}-{month}-{day}'), -4) THEN rcd.id_ticket
        ELSE NULL
      END
  ) AS total_created_tickets_within_four_days,
  COUNT(
    DISTINCT
      CASE
        WHEN rcd.ts_ticket_started >= DATE_ADD(DATE('{year}-{month}-{day}'), -4)
          AND rcd.time_diff <= 4 THEN rcd.previous_id_ticket
        ELSE NULL
      END
  ) AS total_recontact_tickets_within_four_days,
  MAX(rcd.ts_ticket_started) AS ts_last_created_ticket,
  {year} AS year,
  {month} AS month,
  {day} AS day
FROM
  recontact_check_diff AS rcd
GROUP BY 1, 2
