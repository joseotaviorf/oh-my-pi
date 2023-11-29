WITH house_listing AS (
  SELECT
    hl.id_house,
    hl.id_house_listing,
    h.id_user,
    hl.ts_listing_version_start,
    COALESCE(hl.ts_listing_version_end, NOW()) AS ts_listing_version_end
  FROM
    datalake_ebdb_listing.house_listing AS hl
  LEFT JOIN
    datalake_ebdb_listing.house AS h
      ON h.id = hl.id_house
),
photo_jobs AS (
  SELECT
    turf.*,
    CAST(COALESCE(dhl.id_house_listing, hl_photo.id_house_listing, '-1') AS BIGINT) AS sk_house_listing,
    CAST(COALESCE(hl_photo.id_user, dhl.id_user, '-1') AS BIGINT) AS sk_house_owner,
    CAST(COALESCE(fpj.id, '-1') AS BIGINT) AS sk_photo_job,
    CAST(COALESCE(fpj.id_rep, '-1') AS BIGINT) AS sk_user_sales_rep
  FROM
    datalake_crm_tasks_flows.tasks_users_resolutions_flow AS turf
  LEFT JOIN
    datalake_ebdb_photo_jobs.photo_job fpj
      ON turf.origin = 'JobFotografo'
      AND CAST(CAST(turf.id_origin AS DECIMAL) AS BIGINT) = CAST(fpj.id AS BIGINT)
  LEFT JOIN
    house_listing AS hl_photo
      ON hl_photo.id_house = fpj.id_house
      AND fpj.ts_created BETWEEN hl_photo.ts_listing_version_start AND hl_photo.ts_listing_version_end
      AND hl_photo.id_house_listing IS NOT NULL
  LEFT JOIN
    house_listing AS dhl
      ON turf.origin = 'Imovel'
      AND CAST(CAST(turf.id_origin AS DECIMAL) AS BIGINT) = CAST(dhl.id_house AS BIGINT)
      AND turf.ts_start BETWEEN COALESCE(NULLIF(dhl.ts_listing_version_start,''), turf.ts_start, NOW()) AND dhl.ts_listing_version_end
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
    CAST(id_house_listing AS BIGINT) AS sk_house_listing,
    CAST(id_user AS BIGINT) AS sk_house_owner
  FROM
    house_listing
  WHERE
    id_house_listing IS NOT NULL
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