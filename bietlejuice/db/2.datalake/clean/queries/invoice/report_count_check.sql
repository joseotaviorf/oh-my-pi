select count(*)
from datalake_clean.invoice
where ym = '{year-month}'
;