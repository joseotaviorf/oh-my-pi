select count(*)
from datalake_clean.invoice_fine
where ym = '{year-month}'
;