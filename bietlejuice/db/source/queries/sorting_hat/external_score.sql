select
	id,
	cpf,
	source,
	value,
	created_at
from "ExternalScore"
where date(created_at) <= date('{execution_date}')
;