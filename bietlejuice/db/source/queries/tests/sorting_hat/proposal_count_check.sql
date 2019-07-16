select count(*)
from "Proposal"
where date(analysis_date) <= date('{execution_date}')
;