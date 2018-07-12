select
  contract_id,
  fine,
  due_date,
  paid_date,
  ym as ym_partition
from datalake_clean.invoice_fine
where ym = '{year_month}'