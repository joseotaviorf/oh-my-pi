SELECT
  id AS id_contact_submission_type,
  type,
  version,
  created_at AS ts_created_at,
  updated_at AS ts_updated_at,
  YEAR(ts_created_at) AS year,
  MONTH(ts_created_at) AS month,
  DAY(ts_created_at) as day
FROM
  datalake_demand_contact_submission_raw.contact_submission_types
