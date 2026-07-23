SELECT
  id,
  id_onboarding,
  id_address,
  id_supplier,
  id_supplier_city,
  id_google_drive,
  id_google_drive_file,
  status,
  type,
  ownership,
  ownership_cpf,
  installation_code,
  total_debit,
  is_on,
  is_active,
  is_deleted,
  ts_created,
  ts_updated
FROM (
  SELECT
    id,
    id_onboarding,
    id_address,
    id_supplier,
    id_supplier_city,
    id_google_drive,
    id_google_drive_file,
    status,
    type,
    ownership,
    ownership_cpf,
    installation_code,
    total_debit,
    is_on,
    is_active,
    is_deleted,
    ts_created,
    ts_updated,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) AS _w
  FROM datalake_mission_control_clean.onboarding_bill
) AS _t
WHERE
  _w = 1