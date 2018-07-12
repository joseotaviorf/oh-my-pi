select count(1)
from datalake_clean.invoice_fine
where ym = '{year-month}'
;