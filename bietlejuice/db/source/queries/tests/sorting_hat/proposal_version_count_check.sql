select count(*)
from "ProposalVersion"
where date(analysis_date) <= date('{execution_date}')
;