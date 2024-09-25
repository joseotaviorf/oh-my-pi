SELECT
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
  COUNT(DISTINCT
    CASE
      WHEN ft.first_csat_score IN (1, 2) THEN ft.sk_ticket
    END)
  AS amount_dissatisfied,
  (COUNT(DISTINCT
      CASE
        WHEN ft.first_csat_score IS NOT NULL THEN ft.sk_ticket
    END))
  AS amount_responses,
  CAST(
    COUNT(DISTINCT
      CASE
        WHEN ft.first_csat_score IN (1, 2) THEN ft.sk_ticket
          END) * 1.0
        /NULLIF((COUNT(DISTINCT
          CASE
            WHEN ft.first_csat_score IS NOT NULL THEN ft.sk_ticket
    END) * 1.0000),0) AS DECIMAL (10,4))
  AS dsat_rate,
  DATE(ft.ts_csat_first_response) AS dt_csat_responsed
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
WHERE
  ft.ts_started >= CAST('2021-01-01' AS DATE)
GROUP BY
  ALL