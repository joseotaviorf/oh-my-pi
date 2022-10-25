SELECT 
  id AS id_contact_submission_type,
  rev,
  revend,
  revtype,
  type,
  type_mod,
  created_at AS ts_created_at,
  updated_at AS ts_updated_at,
  year,
  month,
  day
FROM
  datalake_demand_contact_submission_raw.contact_submission_types_aud
WHERE
  year = {year}
  AND month = {month}
  AND day = {day}