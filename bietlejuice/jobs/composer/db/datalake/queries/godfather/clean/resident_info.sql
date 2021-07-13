SELECT
  id,
  name,
  version,
  lives_with,
  pets_description,
  number_of_kids,
  user_introduction,
  have_pets as has_pets,
  number_of_cohabitants,
  created_at as ts_created,
  updated_at as ts_updated
FROM
  datalake_godfather_raw.resident_info
