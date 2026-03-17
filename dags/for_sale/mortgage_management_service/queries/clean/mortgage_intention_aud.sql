SELECT
  id,
  rev,
  revtype,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_mortgage_management_service_raw.mortgage_intention_aud
