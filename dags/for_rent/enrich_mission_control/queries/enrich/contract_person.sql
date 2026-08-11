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
FROM (
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
    ts_updated,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) AS _w
  FROM datalake_mission_control_clean.contract_person
) AS _t
WHERE
  _w = 1