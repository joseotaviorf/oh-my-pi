SELECT 
  id,
  house_id AS id_house,
  actor_user_id AS id_actor_user,
  entry_access_id AS id_entry_access,
  channel,
  actor_role,
  event_type,
  entry_access_type,
  entry_access_model,
  entry_access_details,
  key_holder_role,
  key_holder_type,
  key_holder_identifier,
  key_holder_name,
  key_holder_contact,
  key_holder_location,
  actor_user_type,
  key_holder_business_context,
  created_at AS ts_created,
  updated_at AS ts_updated
FROM 
  datalake_ebdb_raw.EntryAccessTracking