SELECT 
  id,
  house_id AS id_house,
  access_model,
  access_type,
  access_code,
  access_details,
  location,
  created_at AS ts_created,
  updated_at AS ts_updated
FROM 
  datalake_ebdb_raw.EntryAccess