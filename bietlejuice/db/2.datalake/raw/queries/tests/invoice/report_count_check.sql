select count(*)
from datalake_raw.seubarriga_invoice
where ym = '{year-month}'
;