SELECT
	inspection_uuid AS uuid_inspection,
	rev,
	revtype AS rev_type,
	revend AS rev_end,
	key,
	value,
	created_by_email,
	created_at_mod AS mod_ts_created,
	updated_at_mod AS mod_ts_updated,
	value_mod AS mod_value,
	created_at AS ts_created,
	updated_at AS ts_updated
FROM
	datalake_inspection_services_raw.annotation_aud
