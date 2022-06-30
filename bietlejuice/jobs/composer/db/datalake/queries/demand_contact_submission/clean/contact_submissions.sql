SELECT 
  id AS id_contact_submission,
  contact_type_id AS id_contact_type,
  business_context,
  origin,
  message,
  user_name,
  user_email,
  phone_country_code,
  phone_number,
  metadata,
  version,
  created_at AS ts_created_at,
  year,
  month,
  day
FROM
  datalake_demand_contact_submission_raw.contact_submissions
WHERE
  year = {year}
  AND month = {month}
  AND day = {day}