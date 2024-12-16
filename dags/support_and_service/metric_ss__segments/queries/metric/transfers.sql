WITH segments_perspective AS (
  SELECT DISTINCT
    fcc.sk_interaction,
    fcc.sk_contact,
    CASE
      WHEN fcc.channel = 'chat' THEN fcc.status
      WHEN fcc.channel = 'call' AND fcc.sk_task  IS NULL THEN 'ABANDONED'
      WHEN fcc.channel = 'call' AND fcc.is_last_interaction = True THEN 'COMPLETED'
      WHEN fcc.channel = 'call' THEN 'TRANSFERRED'
    END AS status,
    fcc.is_first_department_interaction,
    LEAD(dd.team) OVER(PARTITION BY fcc.sk_contact ORDER BY fcc.ts_reservation_created) AS transferred_to_team,
    fcc.channel,
    dd.department,
    dd.board,
    dd.team,
    dd.area,
    dd.front_or_back,
    dt.journey,
    dd.journey_step,
    dt.customer_type_tag AS customer_type,
    fcc.ts_reservation_created AS ts_created
  FROM
    dw_customer_support.fact_customer_contacts AS fcc
  LEFT JOIN
    dw_customer_support.dim_ticket AS dit
      ON dit.sk_ticket = fcc.sk_ticket
  LEFT JOIN
    dw_customer_support.dim_department AS dd
      ON dd.sk_department = fcc.sk_department
  LEFT JOIN
    dw_customer_support.dim_taxonomy AS dt
      ON dt.sk_taxonomy = dit.sk_taxonomy
)
SELECT DISTINCT
  channel,
  journey,
  journey_step,
  department,
  board,
  team,
  area,
  customer_type,
  COUNT(DISTINCT
    CASE
      WHEN status = 'TRANSFERRED'
        AND is_first_department_interaction = True
        AND transferred_to_team <> 'Inside Sales'
        AND channel IN ('call', 'chat')
        AND area = 'CX'
        AND front_or_back = 'front'
      THEN sk_interaction END)
  AS amount_interactions,
  COUNT(DISTINCT
      CASE
            WHEN channel IN ('call', 'chat')
                AND area = 'CX'
                AND front_or_back = 'front'
              THEN sk_contact
        END)
  AS amount_contacts,
  CAST(COUNT(DISTINCT
    CASE
      WHEN status = 'TRANSFERRED'
        AND is_first_department_interaction = True
        AND transferred_to_team <> 'Inside Sales'
        AND channel IN ('call', 'chat')
        AND area = 'CX'
        AND front_or_back = 'front'
      THEN sk_interaction END)
  / NULLIF((COUNT(DISTINCT
      CASE
        WHEN channel IN ('call', 'chat')
          AND area = 'CX'
          AND front_or_back = 'front'
        THEN sk_contact
        END)*1.000) ,0) AS DECIMAL(10,4))
  AS transfer_rate,
  DATE(ts_created) AS dt_segment_created
FROM
  segments_perspective
GROUP BY ALL
