select count(1)
from datalake_raw.seubarriga_invoice
where ym = '{year-month}'
;