SELECT 
  id AS id_contact_submission,
  contact_type_id AS id_contact_type,
  rev,
  revend,
  revtype,
  business_context,
  business_context_mod,
  origin,
  origin_mod,
  contact_type_id_mod,
  message,
  message_mod,
  user_name,
  user_name_mod,
  user_email,
  user_email_mod,
  phone_country_code,
  phone_country_code_mod,
  phone_number,
  phone_number_mod,
  metadata,
  metadata_mod,
  created_at AS ts_created_at,
  updated_at AS ts_updated_at,
  year,
  month,
  day
FROM
  datalake_demand_contact_submission_raw.contact_submissions_aud
WHERE
  year = {year}
  AND month = {month}
  AND day = {day}