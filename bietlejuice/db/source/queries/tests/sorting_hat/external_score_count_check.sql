select count(1)
from "ExternalScore"
where date(created_at) <= date('{execution_date}')
;