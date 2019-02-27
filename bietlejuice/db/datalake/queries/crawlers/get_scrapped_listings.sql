select *
from datalake_raw.crawlers
where started_on = date '{started_on}' and ws = '{ws}';