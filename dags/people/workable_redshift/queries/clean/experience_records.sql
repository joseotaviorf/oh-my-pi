SELECT
  id,
  job_id AS id_job,
  candidate_id AS id_candidate,
  job_title,
  candidate_name,
  experience_title,
  summary,
  company,
  industry,
  CURRENT AS is_current,
  start_date AS dt_started,
  end_date AS dt_ended,
  experience_record_created_at AS ts_created,
  updated_at AS ts_updated,
  NOW() AS ts_load
FROM
  datalake_workable_redshift_raw.experience_records
WHERE
  MAKE_DATE(YEAR, MONTH, DAY) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY 
  updated_at = MAX(updated_at) OVER (
    PARTITION BY
      id
  )