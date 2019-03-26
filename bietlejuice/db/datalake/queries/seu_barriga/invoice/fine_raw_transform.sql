select distinct
  external_id_contract,
  fine,
  regexp_extract(due_date, '(\d+-\d+-\d+)T.*', 1) as dt_due,
  regexp_extract(paid_date, '(\d+-\d+-\d+)T.*', 1) as dt_paid
from datalake_raw.seu_barriga_invoice_fine
where ym = '{year_month}'
;