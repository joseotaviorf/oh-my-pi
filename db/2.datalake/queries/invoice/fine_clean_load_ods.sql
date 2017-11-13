select
  contract_id,
  fine,
  due_date,
  paid_date,
  ym as year_month
from datalake_clean.invoice_fine
where ym = '{year}-{month}'