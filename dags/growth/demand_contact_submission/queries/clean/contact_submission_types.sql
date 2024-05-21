SELECT
  id AS id_contact_submission_type,
  type,
  version,
  created_at AS ts_created_at,
  updated_at AS ts_updated_at,
  year,
  month,
  day
FROM
  datalake_demand_contact_submission_raw.contact_submission_types
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
