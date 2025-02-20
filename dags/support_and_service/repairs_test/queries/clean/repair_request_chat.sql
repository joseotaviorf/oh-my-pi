SELECT
	id,
	repair_request_id AS id_repair_request,
	started_at AS ts_started
from
	datalake_repairs_test_raw.repair_request_chat