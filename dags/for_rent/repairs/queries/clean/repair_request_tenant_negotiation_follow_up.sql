SELECT
	id,
	repair_request_id AS id_repair_request,
	description,
	status,
	help_action,
	solving_action,
	expected_execution_date AS ts_expected_execution,
	reassign_date AS ts_reassign,
	created_at AS ts_created,
	updated_at AS ts_updated,
	year,
	month,
	day
FROM
    datalake_repairs_raw.repair_request_tenant_negotiation_follow_up
