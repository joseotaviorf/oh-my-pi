SELECT
  id,
  candidate_id AS id_candidate,
  payload,
  created_at AS ts_created,
  updated_at AS ts_updated,
  NOW() AS ts_load
FROM
  datalake_workable_redshift_raw.candidate_referrals