WITH segments_perspective AS (
  SELECT DISTINCT
    frc.sk_interaction,
    frc.sk_contact,
    CASE
      WHEN frc.channel = 'chat' THEN frc.status
      WHEN frc.channel = 'call' AND frc.sk_task  IS NULL THEN 'ABANDONED'
      WHEN frc.channel = 'call' AND frc.is_last_interaction = True THEN 'COMPLETED'
      WHEN frc.channel = 'call' THEN 'TRANSFERRED'
    END AS status,
    frc.is_first_department_interaction,
    LEAD(dd.team) OVER(PARTITION BY frc.sk_contact ORDER BY frc.ts_created) AS transferred_to_team,
    frc.channel,
    dd.department,
    dd.board,
    dd.team,
    dd.area,
    dd.front_or_back,
    dt.journey,
    dd.journey_step,
    dt.customer_type_tag AS customer_type,
    frc.ts_created
  FROM
    dw_customer_support.fact_received_contact AS frc
  LEFT JOIN
    dw_customer_support.dim_department AS dd
      ON dd.sk_department = frc.sk_department
  LEFT JOIN
    dw_customer_support.dim_taxonomy AS dt
      ON dt.sk_taxonomy = frc.sk_taxonomy
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
GROUP BY
  ALL
