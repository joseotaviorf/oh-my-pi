SELECT
  id,
  mortgage_intention_id AS id_mortgage_intention,
  sale_reference_id,
  inspection_companion_name AS inspection_companion_person_name,
  inspection_companion_phone AS inspection_companion_phone_number,
  version,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_mortgage_management_service_raw.mortgage_intention_sale_details
