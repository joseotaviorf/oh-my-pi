SELECT
  id,
  name,
  rev,
  revtype as rev_type,
  lives_with,
  pets_description,
  number_of_kids,
  user_introduction,
  have_pets as has_pets,
  number_of_cohabitants
FROM datalake_godfather_raw.audit_resident_info_aud
