WITH base_tickets AS (
  SELECT
  t.id_user_main AS id_user,
  t.id_ticket,
  cs.last_csat_score AS csat_score,
  cs.ts_first_response AS ts_csat_response
FROM
  datalake_customer_support.tickets AS t
LEFT JOIN
  datalake_customer_support.csat AS cs
    ON cs.id_ticket = t.id_ticket
WHERE
  t.id_user_main IS NOT NULL
  AND cs.last_csat_score IS NOT NULL
  AND DATE(cs.ts_first_response) <= DATE('{year}-{month}-{day}')
),
csat_score AS (
  SELECT
    bt.id_user,
    bt.id_ticket,
    bt.csat_score,
    bt.ts_csat_response,
    ROW_NUMBER() OVER(PARTITION BY bt.id_user ORDER BY bt.ts_csat_response DESC) AS order_csat
  FROM
    base_tickets AS bt
)
SELECT
  DATE_FORMAT(DATE('{year}-{month}-{day}'), 'yyyyMMdd') AS id_snapshot,
  cs.id_user,
  MAX(
    CASE
      WHEN cs.order_csat = 1 THEN cs.csat_score
    END
  ) AS last_human_csat_answered_score,
  COUNT(
    DISTINCT
      cs.id_ticket
  ) AS total_human_csat_answered,
  COUNT(
    DISTINCT
      CASE
        WHEN cs.csat_score IN (4,5) THEN cs.id_ticket
      END
  ) AS total_human_csat_promoter,
  COUNT(
    DISTINCT
      CASE
        WHEN cs.csat_score = 3 THEN cs.id_ticket
      END
  ) AS total_human_csat_neutral,
  COUNT(
    DISTINCT
      CASE
        WHEN cs.csat_score IN (1,2) THEN cs.id_ticket
      END
  ) AS total_human_csat_detractor,
  ROUND(
    AVG(
      CASE
        WHEN DATE(cs.ts_csat_response) >= DATE('{year}-{month}-{day}') - INTERVAL 3 month THEN cs.csat_score
      END
    ), 2
   ) AS avg_human_csat_score_within_three_months,
  COUNT(
    CASE
      WHEN DATE(cs.ts_csat_response) >= DATE('{year}-{month}-{day}') - INTERVAL 3 month
        AND cs.csat_score IN (1,2) THEN cs.id_ticket
    END
  ) AS total_human_csat_detractor_within_three_months,
  COUNT(
    CASE
      WHEN DATE(cs.ts_csat_response) >= DATE('{year}-{month}-{day}') - INTERVAL 3 month
        AND cs.csat_score = 3 THEN cs.id_ticket
      END
  ) AS total_human_csat_neutral_within_three_months,
  COUNT(
    CASE
      WHEN DATE(cs.ts_csat_response) >= DATE('{year}-{month}-{day}') - INTERVAL 3 month
        AND cs.csat_score IN (4, 5) THEN cs.id_ticket
    END
  ) AS total_human_csat_promoter_within_three_months,
  COUNT(
    CASE
      WHEN DATE(cs.ts_csat_response) >= DATE('{year}-{month}-{day}') - INTERVAL 3 month THEN cs.id_ticket
    END
  ) AS total_human_csat_answered_within_three_months,
  ROUND(
    (
      COUNT(
        CASE
          WHEN DATE(cs.ts_csat_response) >= DATE('{year}-{month}-{day}') - INTERVAL 3 month
            AND cs.csat_score IN (1,2) THEN cs.id_ticket
          END
      )/
      COUNT(
        CASE
          WHEN DATE(cs.ts_csat_response) >= DATE('{year}-{month}-{day}') - INTERVAL 3 month THEN cs.id_ticket
        END
      )
    ) * 100, 2
  ) AS human_csat_detractor_percentage_within_three_months,
  MAX(
    CASE
      WHEN DATE(cs.ts_csat_response) >= DATE('{year}-{month}-{day}') - INTERVAL 3 month THEN TRUE
      ELSE FALSE
    END
  ) AS has_answered_human_csat_within_three_months,
  MAX(
    CASE
      WHEN cs.order_csat = 1 THEN cs.ts_csat_response
    END
  ) AS ts_last_human_csat_created,
  {year} AS year,
  {month} AS month,
  {day} AS day
FROM
  csat_score AS cs
GROUP BY 1, 2
