SELECT
  id,
  candidate_id AS id_candidate,
  job_id AS id_job,
  member_id AS id_member,
  signable_template_id AS id_signable_template,
  decline_reason,
  state,
  locale,
  visibility_mask,
  state_updated_at AS ts_state_updated,
  created_at AS ts_created,
  updated_at AS ts_updated,
  NOW() AS ts_load
FROM
  datalake_workable_redshift_raw.offers
WHERE
  MAKE_DATE(YEAR, MONTH, DAY) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY
  updated_at = MAX(updated_at) OVER (
    PARTITION BY
      id
  )