select count(*)
from invoice.fine
where ym_partition = '{year_month}'
;