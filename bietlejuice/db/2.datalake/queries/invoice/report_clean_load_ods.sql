select
  contract_id,
  trim(version) as version,
  blocked,
  trim("_from") as "_from",
  trim("_to") as "_to",
  trim(description) as description,
  amount,
  trim(item) as item,
  trim(ref_item_ym) as ref_item_ym,
  trim(due_date) as due_date,
  trim(tenant_due_date) as tenant_due_date,
  trim(tenant_paid_date) as tenant_paid_date,
  trim(tenant_status) as tenant_status,
  trim(landlord_due_date) as landlord_due_date,
  trim(landlord_paid_date) as landlord_paid_date,
  trim(landlord_status) as landlord_status,
  cast(delayed_days as smallint) as delayed_days,
  ym as ym_partition,
  trim(purpose) as purpose
from datalake_clean.invoice
where ym = '{year_month}'
;