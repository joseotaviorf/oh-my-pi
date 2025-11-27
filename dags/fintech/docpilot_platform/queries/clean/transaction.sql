SELECT
	id,
	remote_addr AS remote_address,
	issued_at AS ts_issued
FROM datalake_docpilot_platform_raw.transaction
