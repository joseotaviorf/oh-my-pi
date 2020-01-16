select count(*)
from "ProposalVersion"
where date(created_at) <= date('{execution_date}')
;