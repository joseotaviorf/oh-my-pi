select count(*)
from invoice.report
where ym_partition = '{year_month}'
;