SELECT
  id AS id_contact_submission,
  contact_type_id AS id_contact_type,
  GET_JSON_OBJECT(metadata, '$.userId') AS id_user,
  GET_JSON_OBJECT(metadata, '$.houseId') AS id_house,
  GET_JSON_OBJECT(metadata, '$.regionId') AS id_region,
  GET_JSON_OBJECT(metadata, '$.abSecretariatTag') AS secretariat_tag,
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
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
