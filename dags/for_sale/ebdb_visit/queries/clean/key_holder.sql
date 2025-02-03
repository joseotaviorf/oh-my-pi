SELECT 
  id,
  entry_access_id AS id_entry_access,
  holder_type,
  holder_name,
  holder_role,
  holder_contact,
  holder_identifier,
  holder_location,
  updated_at AS ts_updated,
  created_at AS ts_created
FROM 
  datalake_ebdb_raw.KeyHolder