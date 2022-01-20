WITH photo_jobs AS (
  SELECT
    turf.*,
    CAST(COALESCE(dhl.sk_house_listing, dhl_no_version.sk_house_listing, fhl_photo.sk_house_listing, '-1') AS BIGINT) AS sk_house_listing,
    CAST(COALESCE(fhl_photo.sk_owner, fhl.sk_owner, fhl_no_version.sk_owner, '-1') AS BIGINT) AS sk_house_owner,
    CAST(COALESCE(fpj.id_photo_job, '-1') AS BIGINT) AS sk_photo_job,
    CAST(COALESCE(fpj.sk_user_rep, '-1') AS BIGINT) AS sk_user_sales_rep
  FROM
    datalake_crm_tasks_flows.tasks_users_resolutions_flow AS turf
  LEFT JOIN 
    dw_janus.fact_photo_job fpj
      ON turf.origin = 'JobFotografo'
      AND CAST(CAST(turf.id_origin AS DECIMAL) AS BIGINT) = CAST(fpj.id_photo_job AS BIGINT)
  LEFT JOIN 
    dw_public.fact_house_listings fhl_photo
      ON fhl_photo.sk_house_listing = fpj.sk_house_listing
      AND fhl_photo.sk_house_listing != '-1'
  LEFT JOIN 
    dw_public.dim_house_listing dhl
      ON turf.origin = 'Imovel'
      AND CAST(CAST(turf.id_origin AS DECIMAL) AS BIGINT) = CAST(dhl.id_house AS BIGINT)
      AND turf.ts_start BETWEEN COALESCE(NULLIF(dhl.ts_listing_version_start,''), turf.ts_start, NOW()) AND COALESCE(NULLIF(dhl.ts_listing_version_end, ''), NOW())
  LEFT JOIN 
    dw_public.fact_house_listings fhl
      ON fhl.sk_house_listing = dhl.sk_house_listing
      AND fhl.sk_house_listing != '-1'
  LEFT JOIN 
    dw_public.dim_house_listing dhl_no_version
      ON (turf.origin) = 'Imovel'
      AND turf.id_origin = dhl_no_version.id_house
      AND dhl_no_version.ts_listing_version_start = ''
  LEFT JOIN 
    dw_public.fact_house_listings fhl_no_version
      ON fhl_no_version.sk_house_listing = dhl_no_version.sk_house_listing
  WHERE
    turf.year = {year}
    AND turf.month = {month}
    AND turf.day = {day}
    AND turf.type IN (
                    'FupFoto',
                    'AgendarJobDeFotografo'
                   )
),
photo_job_house_listing AS (
  SELECT
    CAST(sk_house_listing AS BIGINT) AS sk_house_listing,
    CAST(sk_owner AS BIGINT) AS sk_house_owner
  FROM 
    dw_public.fact_house_listings
  WHERE 
    sk_house_listing != '-1'
  GROUP BY 1, 2
)
SELECT DISTINCT
  pj.id_task AS sk_task,
  pj.sk_photo_job,
  pj.id_action_date AS sk_action_date,
  pj.id_assignee AS sk_assignee,
  pj.id_completed_date AS sk_completed_date,
  pj.sk_house_listing,
  COALESCE(pjhl.sk_house_owner, pj.sk_house_owner) AS sk_house_owner,
  COALESCE(CAST(pj.id_origin AS BIGINT), -1) AS sk_origin,
  pj.id_receiver AS sk_receiver,
  pj.id_start_date AS sk_start_date,
  pj.id_task_user_end_date AS sk_task_action_end_date,
  pj.id_task_user_start_date AS sk_task_action_start_date,
  pj.id_user_action AS sk_user_action,
  pj.sk_user_sales_rep,
  pj.action_type,
  pj.action_user_name,
  pj.task_user_type AS task_action_type,
  pj.task_user_resolve_hours AS task_user_action_resolve_hours,
  pj.ts_action,
  pj.ts_task_user_end AS ts_task_action_end,
  pj.ts_task_user_start AS ts_task_action_start,
  NOW() AS ts_load,
  pj.year,
  pj.month,
  pj.day
FROM 
  photo_jobs pj
LEFT JOIN 
  photo_job_house_listing pjhl
    ON pj.sk_house_listing = pjhl.sk_house_listing
    AND pj.sk_photo_job = -1