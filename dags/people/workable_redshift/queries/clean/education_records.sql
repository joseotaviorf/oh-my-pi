SELECT
  id,
  job_id AS id_job,
  candidate_id AS id_candidate,
  job_title,
  candidate_name,
  degree,
  school,
  field_of_study,
  start_date AS dt_started,
  end_date AS dt_ended,
  education_record_created_at AS ts_created,
  updated_at AS ts_update,
  NOW() AS ts_load
FROM
  datalake_workable_redshift_raw.education_records
WHERE
  MAKE_DATE(YEAR, MONTH, DAY) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY 
  updated_at = MAX(updated_at) OVER (
    PARTITION BY
      id
  )