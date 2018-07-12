select count(1)
from datalake_raw.seubarriga_invoice_fine
where ym = '{year-month}'
;