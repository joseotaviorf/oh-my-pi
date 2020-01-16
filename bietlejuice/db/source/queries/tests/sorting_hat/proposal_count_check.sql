select count(*)
from "Proposal"
where date(created_at) <= date('{execution_date}')
;