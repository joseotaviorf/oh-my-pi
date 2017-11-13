select
  contract_id,
  version,
  blocked,
  "from",
  "to",
  description,
  amount,
  item,
  year_month as ref_item_ym,
  due_date,
  tenant_due_date,
  tenant_paid_date,
  tenant_status,
  landlord_due_date,
  landlord_paid_date,
  landlord_status,
  cast(delayed_days as smallint) as delayed_days,
  ym as year_month
from datalake_clean.invoice
where ym = '{year}-{month}'