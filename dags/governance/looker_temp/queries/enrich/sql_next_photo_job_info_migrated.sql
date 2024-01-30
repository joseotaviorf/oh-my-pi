SELECT
  sk_photo_job,
  LAG(sk_photo_job, 1) OVER (PARTITION BY imovel_id ORDER BY sk_photo_job DESC) AS next_sk_photo_job,
  LAG(dt_job_scheduled, 1) OVER (PARTITION BY imovel_id ORDER BY sk_photo_job DESC) AS dt_next_job_scheduled,
  LAG(dt_job_created, 1) OVER (PARTITION BY imovel_id ORDER BY sk_photo_job DESC) AS dt_next_job_created,
  user_cancel_dt AS dt_cancel,
  dt_problem_reported AS dt_problem_reported,
  CASE
    WHEN rescheduled = TRUE
    AND DATEDIFF(
      DAY,
      CAST(user_cancel_dt AS TIMESTAMP),
      CAST(LAG(dt_job_scheduled, 1) OVER (PARTITION BY imovel_id ORDER BY sk_photo_job DESC) AS TIMESTAMP)
    ) > 3.65
    THEN FALSE
    WHEN rescheduled = TRUE
    AND DATEDIFF(
      DAY,
      CAST(user_cancel_dt AS TIMESTAMP),
      CAST(LAG(dt_job_scheduled, 1) OVER (PARTITION BY imovel_id ORDER BY sk_photo_job DESC) AS TIMESTAMP)
    ) <= 3.65
    THEN TRUE
    ELSE NULL
  END AS is_rescheduling_photo_job_sla_achieved,
  CASE
    WHEN rescheduled = TRUE
    AND COALESCE(DATE_TRUNC('WEEK', dt_problem_reported), DATE_TRUNC('WEEK', user_cancel_dt)) = DATE_TRUNC(
      'WEEK',
      LAG(dt_job_scheduled, 1) OVER (PARTITION BY imovel_id ORDER BY sk_photo_job DESC)
    )
    THEN TRUE
    ELSE FALSE
  END AS was_rescheduled_within_same_week
FROM dw_public.dim_photo_job AS dpj
ORDER BY
  1 DESC