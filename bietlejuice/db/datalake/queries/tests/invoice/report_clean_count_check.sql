select count(1)
from datalake_clean.invoice
where ym = '{year_month}'
;