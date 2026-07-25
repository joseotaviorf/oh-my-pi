SELECT
  id_ticket,
  id_photo_job,
  id_house,
  user_sender,
  responsible_analyst_name,
  responsible_analyst_email,
  responsible_analyst_organization AS organization,
  group_name,
  house_classification,
  house_classification_reason,
  classification_comments,
  signboard_location,
  status,
  ts_created,
  ts_created_local,
  dt_analyzed_utc,
  dt_analyzed,
  YEAR(CURRENT_DATE) AS year,
  MONTH(CURRENT_DATE) AS month,
  DAY(CURRENT_DATE) AS day,
  NOW() AS ts_load
FROM
  datalake_listing_jobs.listing_quality_tasks
WHERE
  DATE(dt_analyzed_utc) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
