WITH csat_bot_answers AS (
  SELECT
    rt.id_rating,
    rt.id_user,
    rt.grade,
    rt.ts_created,
    ROW_NUMBER() OVER(PARTITION BY id_user ORDER BY ts_created DESC) AS order_rating
  FROM
    datalake_chat_fup_clean.rating AS rt
  WHERE
    rt.id_user IS NOT NULL
    AND DATE(rt.ts_created) <= DATE('{year}-{month}-{day}')
)
SELECT
  DATE_FORMAT(DATE('{year}-{month}-{day}'), 'yyyyMMdd') AS id_snapshot,
  cba.id_user,
  MAX(
    CASE
      WHEN cba.order_rating = 1 THEN grade
    END
  ) AS last_bot_csat_answered_score,
  COUNT(
    DISTINCT
      cba.id_rating
  ) AS total_bot_csat_answered,
  COUNT(
    DISTINCT
      CASE
        WHEN cba.grade IN (4,5) THEN cba.id_rating
      END
  ) AS total_bot_csat_promoter,
  COUNT(
    DISTINCT
      CASE
        WHEN cba.grade = 3 THEN cba.id_rating
      END
  ) AS total_bot_csat_neutral,
  COUNT(
    DISTINCT
      CASE
        WHEN cba.grade IN (1,2) THEN cba.id_rating
      END
  ) AS total_bot_csat_detractor,
  ROUND(
    AVG(
      CASE
        WHEN DATE(cba.ts_created) >= DATE('{year}-{month}-{day}') - INTERVAL 3 month THEN cba.grade
      END
    ), 2
   ) AS avg_bot_csat_score_within_three_months,
  COUNT(
    CASE
      WHEN DATE(cba.ts_created) >= DATE('{year}-{month}-{day}') - INTERVAL 3 month
        AND cba.grade IN (1,2) THEN cba.id_rating
    END
  ) AS total_bot_csat_detractor_within_three_months,
  COUNT(
    CASE
      WHEN DATE(cba.ts_created) >= DATE('{year}-{month}-{day}') - INTERVAL 3 month
        AND cba.grade = 3 THEN cba.id_rating
      END
  ) AS total_bot_csat_neutral_within_three_months,
  COUNT(
    CASE
      WHEN DATE(cba.ts_created) >= DATE('{year}-{month}-{day}') - INTERVAL 3 month
        AND cba.grade IN (4, 5) THEN cba.id_rating
    END
  ) AS total_bot_csat_promoter_within_three_months,
  COUNT(
    CASE
      WHEN DATE(cba.ts_created) >= DATE('{year}-{month}-{day}') - INTERVAL 3 month THEN cba.id_rating
    END
  ) AS total_bot_csat_answered_within_three_months,
  ROUND(
    (
      COUNT(
        CASE
          WHEN DATE(cba.ts_created) >= DATE('{year}-{month}-{day}') - INTERVAL 3 month
            AND cba.grade IN (1,2) THEN cba.id_rating
          END
      )/
      COUNT(
        CASE
          WHEN DATE(cba.ts_created) >= DATE('{year}-{month}-{day}') - INTERVAL 3 month THEN cba.id_rating
        END
      )
    ) * 100, 2
  ) AS bot_csat_detractor_percentage_within_three_months,
  MAX(
    CASE
      WHEN DATE(cba.ts_created) >= DATE('{year}-{month}-{day}') - INTERVAL 3 month THEN TRUE
      ELSE FALSE
    END
  ) AS has_answered_bot_csat_within_three_months,
  MAX(
    CASE
      WHEN cba.order_rating = 1 THEN cba.ts_created
    END
  ) AS ts_last_bot_csat_created,
  {year} AS year,
  {month} AS month,
  {day} AS day
FROM
  csat_bot_answers AS cba
GROUP BY 1, 2
