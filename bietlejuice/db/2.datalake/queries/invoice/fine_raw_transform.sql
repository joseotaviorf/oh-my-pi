select distinct
   "contract-external-id",
  fine,
  regexp_extract(due_date, '(\d+-\d+-\d+)T.*', 1) as "due-date",
  regexp_extract("paid-date", '(\d+-\d+-\d+)T.*', 1) as "paid-date"
from datalake_raw.seubarriga_invoice_fine
where ym = '{year_month}'
;