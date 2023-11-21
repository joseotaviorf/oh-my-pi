SELECT
  id,
  id_contract,
  id_address,
  id_user,
  contract_type,
  person_type,
  full_name,
  phone_number,
  document_number,
  is_deleted,
  ts_created,
  ts_updated
FROM 
  datalake_mission_control_clean.contract_person
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) = 1