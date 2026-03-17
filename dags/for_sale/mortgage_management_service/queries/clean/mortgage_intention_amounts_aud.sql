SELECT
  id,
  rev,
  revtype,
  mortgage_intention_id AS id_mortgage_intention,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_mortgage_management_service_raw.mortgage_intention_amounts_aud
