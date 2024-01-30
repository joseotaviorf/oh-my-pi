WITH aux_rescheduled_photographer AS (
  SELECT
    fpj.sk_house_listing,
    CASE
      WHEN dpj.cancel_reason = 'IMMEDIATE_RESCHEDULING_BY_PHOTOGRAPHER'
      THEN TRUE
    END AS `IMMEDIATE_RESCHEDULING_BY_PHOTOGRAPHER`
  FROM dw_public.fact_photo_job AS fpj
  LEFT JOIN dw_public.dim_photo_job AS dpj
    ON dpj.sk_photo_job = fpj.id_photo_job
  LEFT JOIN dw_public.dim_date AS ds
    ON fpj.sk_date_job_created = ds.sk_date
  WHERE
    CASE
      WHEN dpj.cancel_reason = 'IMMEDIATE_RESCHEDULING_BY_PHOTOGRAPHER'
      THEN TRUE
    END = TRUE
), aux_rescheduled_iss AS (
  SELECT DISTINCT
    fpj.sk_house_listing,
    CASE
      WHEN dpj.cancel_reason = 'IMMEDIATE_RESCHEDULING'
      OR dpj.cancel_reason = 'MANUAL_RESCHEDULING'
      THEN TRUE
    END AS `IMMEDIATE_RESCHEDULING`
  FROM dw_public.fact_photo_job AS fpj
  LEFT JOIN dw_public.dim_photo_job AS dpj
    ON dpj.sk_photo_job = fpj.id_photo_job
  LEFT JOIN dw_public.dim_date AS ds
    ON fpj.sk_date_job_created = ds.sk_date
  WHERE
    CASE
      WHEN dpj.cancel_reason = 'IMMEDIATE_RESCHEDULING'
      OR dpj.cancel_reason = 'MANUAL_RESCHEDULING'
      THEN TRUE
    END = TRUE
), aux_rescheduled AS (
  SELECT DISTINCT
    fpj.sk_house_listing,
    CASE WHEN dpj.rescheduled = TRUE THEN TRUE END AS `was_rescheduled`
  FROM dw_public.fact_photo_job AS fpj
  LEFT JOIN dw_public.dim_photo_job AS dpj
    ON dpj.sk_photo_job = fpj.id_photo_job
  LEFT JOIN dw_public.dim_date AS ds
    ON fpj.sk_date_job_created = ds.sk_date
  WHERE
    CASE WHEN dpj.rescheduled = TRUE THEN TRUE END = TRUE
)
SELECT
  dmop.sk_house_listing,
  TO_TIMESTAMP(CAST(dmop.sk_opportunity_date AS STRING), 'yyyyMMdd') AS dt_opportunity,
  CASE
    WHEN IMMEDIATE_RESCHEDULING_BY_PHOTOGRAPHER = TRUE
    THEN 'IMMEDIATE_RESCHEDULING_BY_PHOTOGRAPHER'
    WHEN IMMEDIATE_RESCHEDULING = TRUE
    THEN 'IMMEDIATE_RESCHEDULING'
    ELSE 'NOT_RESCHEDULED'
  END AS reagendamento,
  dpj2.job_status AS last_photo_job_status
FROM dw_datamarts.datamart_opportunity AS dmop
LEFT JOIN aux_rescheduled_photographer AS arp
  ON SUBSTR(CAST(arp.sk_house_listing AS STRING), 1, 9) = SUBSTR(CAST(dmop.sk_house_listing AS STRING), 1, 9)
LEFT JOIN aux_rescheduled_iss AS ari
  ON SUBSTR(CAST(ari.sk_house_listing AS STRING), 1, 9) = SUBSTR(CAST(dmop.sk_house_listing AS STRING), 1, 9)
LEFT JOIN aux_rescheduled AS ar
  ON SUBSTR(CAST(ar.sk_house_listing AS STRING), 1, 9) = SUBSTR(CAST(dmop.sk_house_listing AS STRING), 1, 9)
LEFT JOIN dw_public.dim_photo_job AS dpj
  ON dpj.sk_photo_job = dmop.sk_first_photo_job
LEFT JOIN dw_public.dim_photo_job AS dpj2
  ON dpj2.sk_photo_job = dmop.sk_last_photo_job
WHERE
  TO_TIMESTAMP(CAST(dmop.sk_opportunity_date AS STRING), 'yyyyMMdd') >= CAST(CAST('2021-11-01' AS DATE) AS DATE)
ORDER BY
  2 DESC