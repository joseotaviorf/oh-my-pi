SELECT
  id as sk_inspection,
  id as id_inspection,
  mode,
  status,
  type,
  is_tenant_approved,
  is_owner_approved,
  has_inspector_comment,
  has_tenant_comment,
  has_owner_comment,
  ts_created,
  ts_expired,
  ts_first_synced,
  ts_last_synced,
  now() as ts_load
from datalake_ebdb_listing_jobs.inspection