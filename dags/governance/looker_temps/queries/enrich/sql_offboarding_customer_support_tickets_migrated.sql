WITH channel_frequency AS (
  SELECT
    ct.id_termination,
    ft.channel,
    COUNT(DISTINCT sk_ticket) AS num_tickets
  FROM datalake_offboarding.contract_termination AS ct
  LEFT JOIN dw_customer_support.fact_ticket AS ft
    ON ct.id_contract = ft.sk_contract
  WHERE
    ct.status <> 'CANCELED'
    AND (
      ft.first_department LIKE '%OFF%' OR ft.main_department LIKE '%OFF%'
    )
  GROUP BY
    1,
    2
), channel_rank AS (
  SELECT
    id_termination,
    channel,
    num_tickets,
    ROW_NUMBER() OVER (PARTITION BY id_termination ORDER BY num_tickets DESC) AS num_row
  FROM channel_frequency
)
SELECT
  ct.id_termination,
  cr.channel AS most_frequent_channel,
  COUNT(DISTINCT ft.sk_ticket) AS total_tickets,
  COUNT(DISTINCT CASE WHEN dt.customer_type_tag = 'tenant' THEN ft.sk_ticket END) AS num_tenant_tickets,
  COUNT(DISTINCT CASE WHEN dt.customer_type_tag = 'rent_owner' THEN ft.sk_ticket END) AS num_rent_owner_tickets,
  COUNT(DISTINCT CASE WHEN ft.front_or_back = 'front' THEN ft.sk_ticket END) AS num_front_tickets,
  COUNT(DISTINCT CASE WHEN ft.front_or_back = 'back' THEN ft.sk_ticket END) AS num_back_tickets,
  COUNT(DISTINCT CASE WHEN ft.front_or_back = 'undefined' THEN ft.sk_ticket END) AS num_undefined_tickets,
  COUNT(DISTINCT CASE WHEN ft.status IN ('closed', 'solved') THEN ft.sk_ticket END) AS num_ended_tickets,
  COUNT(DISTINCT CASE WHEN ft.status IN ('new', 'open') THEN ft.sk_ticket END) AS num_ongoing_tickets,
  COUNT(DISTINCT CASE WHEN ft.status IN ('hold', 'pending') THEN ft.sk_ticket END) AS num_on_hold_tickets,
  COUNT(DISTINCT CASE WHEN ft.status IN ('deleted') THEN ft.sk_ticket END) AS num_deleted_tickets,
  AVG(ft.csat_score) AS avg_ticket_csat_score
FROM datalake_offboarding.contract_termination AS ct
LEFT JOIN dw_customer_support.fact_ticket AS ft
  ON ct.id_contract = ft.sk_contract
LEFT JOIN dw_customer_support.dim_taxonomy AS dt
  ON ft.sk_taxonomy = dt.sk_taxonomy
LEFT JOIN channel_rank AS cr
  ON ct.id_termination = cr.id_termination AND cr.num_row = 1
WHERE
  ct.status <> 'CANCELED'
  AND (
    ft.first_department LIKE '%OFF%' OR ft.main_department LIKE '%OFF%'
  )
GROUP BY
  1,
  2